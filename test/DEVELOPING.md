
# Skipping stages.

You can skip test stages using environment variables.

For example, you can do an initial test that will create an AMI and set up a running instance with terraform:

    aws-vault exec sog -n -- $SHELL -c "SKIP_logs=true SKIP_cleanup_ami=true SKIP_cleanup_terraform=true go test -count=1 -timeout 30m  -run TestDeployAndBehaviour" 

Then, while developing the local test use the existing setup :

    aws-vault exec sog -n -- $SHELL -c "SKIP_logs=true SKIP_build_ami=true SKIP_deploy_terraform=true SKIP_cleanup_ami=true SKIP_cleanup_terraform=true go test -count=1 -timeout 30m  -run TestDeployAndBehaviour" 

Finally, to remove everything :

    aws-vault exec sog -n -- $SHELL -c "SKIP_logs=true SKIP_build_ami=true SKIP_deploy_terraform=true  SKIP_validate=true go test -count=1 -timeout 30m  -run TestDeployAndBehaviour" 
