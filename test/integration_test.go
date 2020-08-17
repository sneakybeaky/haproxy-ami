package test

import (
	"fmt"
	"github.com/gruntwork-io/terratest/modules/retry"
	"net"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-sdk-go/service/cloudwatchlogs"
	"github.com/aws/aws-sdk-go/service/ssm"
	"github.com/gruntwork-io/terratest/modules/aws"
	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/gruntwork-io/terratest/modules/logger"
	"github.com/gruntwork-io/terratest/modules/packer"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
)

var DefaultRetryablePackerErrors = map[string]string{
	"Script disconnected unexpectedly": "Occasionally, Packer seems to lose connectivity to AWS, perhaps due to a brief network outage",
}

var DefaultTimeBetweenPackerRetries = 15 * time.Second

const DefaultMaxPackerRetries = 3

const workingDir string = "./terraform-packer"

const packerTemplate string = "../build.json"

const awsRegion string = "eu-west-2"

func TestDeployAndBehaviour(t *testing.T) {
	t.Parallel()

	defer test_structure.RunTestStage(t, "cleanup_ami", func() {
		deleteAMI(t, awsRegion, workingDir)
	})

	// At the end of the test, undeploy the web app using Terraform
	defer test_structure.RunTestStage(t, "cleanup_terraform", func() {
		undeployUsingTerraform(t, workingDir)
	})

	// At the end of the test, fetch the most recent syslog entries from each Instance. This can be useful for
	// debugging issues without having to manually SSH to the server.
	defer test_structure.RunTestStage(t, "logs", func() {
		fetchSyslogForInstance(t, awsRegion, workingDir)
	})

	// Build the AMI for the web app
	test_structure.RunTestStage(t, "build_ami", func() {
		buildAMI(t, awsRegion, workingDir)
	})

	// Deploy the web app using Terraform
	test_structure.RunTestStage(t, "deploy_terraform", func() {
		deployUsingTerraform(t, awsRegion, workingDir)
	})

	test_structure.RunTestStage(t, "validate", func() {
		validateInstanceRunningHAProxyStats(t, workingDir)
		validateInstanceRunningHAProxy(t, workingDir, 9102)
		validateInstanceRunningHAProxyPrometheusExporter(t, workingDir)
		validateinstanceRunningSSM(t, workingDir)
		validateInstanceRunningNodeExporter(t, workingDir)
		validateCloudWatchLogs(t, workingDir)
	})
}

func getFromEnv(t *testing.T, workingDir string, outputField string) string {
	logger.Logf(t, "Getting value of %s", outputField)
	var value = os.Getenv(outputField)
	if value == "" {

		terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)
		value = terraform.Output(t, terraformOptions, outputField)
	}

	return value
}

func buildAMI(t *testing.T, awsRegion string, workingDir string) {
	packerOptions := &packer.Options{
		// The path to where the Packer template is located
		Template: packerTemplate,

		// Variables to pass to our Packer build using -var options
		Vars: map[string]string{
			"aws_region": awsRegion,
		},

		// Configure retries for intermittent errors
		RetryableErrors:    DefaultRetryablePackerErrors,
		TimeBetweenRetries: DefaultTimeBetweenPackerRetries,
		MaxRetries:         DefaultMaxPackerRetries,
	}

	// Save the Packer Options so future test stages can use them
	test_structure.SavePackerOptions(t, workingDir, packerOptions)

	// Build the AMI
	amiID := packer.BuildArtifact(t, packerOptions)

	// Save the AMI ID so future test stages can use them
	test_structure.SaveArtifactID(t, workingDir, amiID)
}

func deleteAMI(t *testing.T, awsRegion string, workingDir string) {
	// Load the AMI ID and Packer Options saved by the earlier build_ami stage
	amiID := test_structure.LoadArtifactID(t, workingDir)

	aws.DeleteAmi(t, awsRegion, amiID)
}

func deployUsingTerraform(t *testing.T, awsRegion string, workingDir string) {
	// A unique ID we can use to namespace resources so we don't clash with anything already in the AWS account or
	// tests running in parallel
	uniqueID := random.UniqueId()

	// Give this EC2 Instance and other resources in the Terraform code a name with a unique ID so it doesn't clash
	// with anything else in the AWS account.
	instanceName := fmt.Sprintf("terratest-http-example-%s", uniqueID)

	// Create an EC2 KeyPair that we can use for SSH access
	keyPairName := fmt.Sprintf("terratest-ssh-example-%s", uniqueID)
	keyPair := aws.CreateAndImportEC2KeyPair(t, awsRegion, keyPairName)
	test_structure.SaveEc2KeyPair(t, workingDir, keyPair)

	// Load the AMI ID saved by the earlier build_ami stage
	amiID := test_structure.LoadArtifactID(t, workingDir)

	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: workingDir,

		// Variables to pass to our Terraform code using -var options
		Vars: map[string]interface{}{
			"aws_region":    awsRegion,
			"instance_name": instanceName,
			"ami_id":        amiID,
			"key_pair_name": keyPairName,
			"prefix":        uniqueID,
		},
	}

	// Save the Terraform Options struct, instance name, and instance text so future test stages can use it
	test_structure.SaveTerraformOptions(t, workingDir, terraformOptions)

	// This will run `terraform init` and `terraform apply` and fail the test if there are any errors
	terraform.InitAndApply(t, terraformOptions)
}

func undeployUsingTerraform(t *testing.T, workingDir string) {
	// Load the Terraform Options saved by the earlier deploy_terraform stage
	terraformOptions := test_structure.LoadTerraformOptions(t, workingDir)

	terraform.Destroy(t, terraformOptions)
}

func fetchSyslogForInstance(t *testing.T, awsRegion string, workingDir string) {
	instanceID := getFromEnv(t, workingDir, "instance_id")
	logs := aws.GetSyslogForInstance(t, instanceID, awsRegion)

	logger.Logf(t, "Most recent syslog for Instance %s:\n\n%s\n", instanceID, logs)
}

func validateInstanceRunningHAProxyStats(t *testing.T, workingDir string) {

	t.Run("HAProxy Stats Available", func(t *testing.T) {

		statsURL := getFromEnv(t, workingDir, "stats_url")

		maxRetries := 3
		timeBetweenRetries := 5 * time.Second

		validate := func(statusCode int, body string) bool {
			return 200 == statusCode && strings.Contains(body, "Statistics Report for")
		}
		http_helper.HttpGetWithRetryWithCustomValidation(t, statsURL, maxRetries, timeBetweenRetries, validate)
	})

}

func validateInstanceRunningHAProxy(t *testing.T, workingDir string, port int) {

	t.Run("HAProxy Running", func(t *testing.T) {
		publicIP := getFromEnv(t, workingDir, "public_ip")

		server := fmt.Sprintf("%s:%d", publicIP, port)

		maxRetries := 3
		timeBetweenRetries := 5 * time.Second
		dialTimeout := 5 * time.Second

		_, err := retry.DoWithRetryE(t, fmt.Sprintf("TCP connect to server %s", server), maxRetries, timeBetweenRetries, func() (string, error) {
			conn, err := net.DialTimeout("tcp", server, dialTimeout)
			if conn != nil {
				defer conn.Close()
			}

			return "", err
		})

		if err != nil {
			t.Fatal(err)
		}

	})

}

func validateInstanceRunningHAProxyPrometheusExporter(t *testing.T, workingDir string) {

	t.Run("HAProxy Exporter Running", func(t *testing.T) {

		haproxyExporterURL := getFromEnv(t, workingDir, "haproxy_exporter_url")
		maxRetries := 3
		timeBetweenRetries := 5 * time.Second

		validate := func(statusCode int, body string) bool {
			return 200 == statusCode && strings.Contains(body, "haproxy_up 1")
		}
		http_helper.HttpGetWithRetryWithCustomValidation(t, haproxyExporterURL, maxRetries, timeBetweenRetries, validate)

	})

}

func validateinstanceRunningSSM(t *testing.T, workingDir string) {

	t.Run("Instance Running SSM", func(t *testing.T) {
		instanceID := getFromEnv(t, workingDir, "instance_id")

		ssmClient := aws.NewSsmClient(t, awsRegion)
		input := &ssm.StartSessionInput{
			Target: &instanceID,
		}

		maxRetries := 3
		timeBetweenRetries := 5 * time.Second

		_, err := retry.DoWithRetryE(t, fmt.Sprintf("Creating SSM session to instance %s", instanceID), maxRetries, timeBetweenRetries, func() (string, error) {

			output, err := ssmClient.StartSession(input)

			if err != nil {
				return "", err
			}

			terminateInput := &ssm.TerminateSessionInput{
				SessionId: output.SessionId,
			}
			_, _ = ssmClient.TerminateSession(terminateInput)

			return "", nil
		})

		if err != nil {
			t.Fatalf("unable to create SSM session to instance %s : %v", instanceID, err)
		}

	})

}

func validateInstanceRunningNodeExporter(t *testing.T, workingDir string) {

	t.Run("Instance Running Node Exporter", func(t *testing.T) {
		nodeExportURL := getFromEnv(t, workingDir, "node_export_url")
		maxRetries := 3
		timeBetweenRetries := 5 * time.Second

		validate := func(statusCode int, body string) bool {
			return 200 == statusCode && strings.Contains(body, "go_threads")
		}
		http_helper.HttpGetWithRetryWithCustomValidation(t, nodeExportURL, maxRetries, timeBetweenRetries, validate)

	})

}

func validateCloudWatchLogs(t *testing.T, workingDir string) {

	t.Run("CloudWatch Logs Setup", func(t *testing.T) {
		instanceID := getFromEnv(t, workingDir, "instance_id")
		cwClient := aws.NewCloudWatchLogsClient(t, awsRegion)
		prefix := fmt.Sprintf("/aws/ec2/haproxy-%s", instanceID)

		maxRetries := 3
		timeBetweenRetries := 5 * time.Second

		_, err := retry.DoWithRetryE(t, fmt.Sprintf("Checking log groups at %s", prefix), maxRetries, timeBetweenRetries, func() (string, error) {

			input := &cloudwatchlogs.DescribeLogGroupsInput{
				LogGroupNamePrefix: &prefix,
			}

			output, err := cwClient.DescribeLogGroups(input)

			if err != nil {
				return "", retry.FatalError{
					Underlying: err,
				}
			}

			if len(output.LogGroups) != 1 {
				return "", fmt.Errorf("expecting 1 log group at %s, got %d", prefix, len(output.LogGroups))
			}

			return "", nil
		})

		if err != nil {
			t.Fatal(err)
		}

	})

}
