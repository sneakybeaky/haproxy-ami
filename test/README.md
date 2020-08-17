# Tests for the packer build

This directory holds tests for the packer build for the HA Proxy AMI image.

We use [terratest](https://github.com/gruntwork-io/terratest#terratest) for this - please read the site for a good introduction and general practices.

These tests should just be run in the `master` AWS account without generating sessions keys.

To do this the `aws-vault` invocation looks like :

    aws-vault exec sog -n -- <command>
    
    
 ## Running the end to end integration test
 
This is a complicated, end-to-end integration test. It builds the AMI from `../build.json`, deploys it using the Terraform code in `terraform-packer`, and checks that the haproxy server in the AMI response to requests. The test is broken into "stages" so you can skip stages by setting environment variables (e.g. skip stage `build_ami` by setting the environment variable `SKIP_build_ami=true`), which speeds up iteration when running this test over and over again locally.

Also note that the default timeout for `go test` is 10 minutes which will not be long enough for this, so you will need to override that value using the [`-timeout` flag](https://golang.org/cmd/go/#hdr-Testing_flags)

Go also caches test results. As we're only changing terraform and packer files then we will disable caching via the `-count` flag

    aws-vault exec sog -n -- go test -count=1 -timeout 30m  -run TestDeployAndBehaviour
 
 
## Developing

Refer to the [developing guide](DEVELOPING.md) to see how to skip test stages    
