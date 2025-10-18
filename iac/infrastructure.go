package iac

import (
	"os"

	"github.com/aws/aws-cdk-go/awscdk/v2"
	ec2 "github.com/aws/aws-cdk-go/awscdk/v2/awsec2"
	"github.com/aws/constructs-go/constructs/v10"
	"github.com/aws/jsii-runtime-go"

	"github.com/nxdir-s/homelab/iac/stacks"
)

type InfrastructureStackProps struct {
	awscdk.StackProps
}

func NewInfrastructureStack(scope constructs.Construct, id string, props *InfrastructureStackProps) awscdk.Stack {
	var sprops awscdk.StackProps
	if props != nil {
		sprops = props.StackProps
	}
	stack := awscdk.NewStack(scope, &id, &sprops)

	ec2.Vpc_FromLookup(stack, jsii.String("vpc"), &ec2.VpcLookupOptions{
		IsDefault: jsii.Bool(true),
	})

	return stack
}

func main() {
	defer jsii.Close()

	app := awscdk.NewApp(nil)

	NewInfrastructureStack(app, "Infrastructure", &InfrastructureStackProps{
		awscdk.StackProps{
			Synthesizer: awscdk.NewDefaultStackSynthesizer(&awscdk.DefaultStackSynthesizerProps{}),
			Env:         env(stacks.DevEast),
		},
	})

	app.Synth(nil)
}

func env(name stacks.EnvRegion) *awscdk.Environment {
	switch name {
	case stacks.QAEast:
		return &awscdk.Environment{
			Account: jsii.String(os.Getenv("CDK_DEFAULT_ACCOUNT")),
			Region:  jsii.String(stacks.AWSEast.String()),
		}
	case stacks.QAWest:
		return &awscdk.Environment{
			Account: jsii.String(os.Getenv("CDK_DEFAULT_ACCOUNT")),
			Region:  jsii.String(stacks.AWSWest.String()),
		}
	case stacks.ProdEast:
		return &awscdk.Environment{
			Account: jsii.String(os.Getenv("CDK_DEFAULT_ACCOUNT")),
			Region:  jsii.String(stacks.AWSEast.String()),
		}
	case stacks.ProdWest:
		return &awscdk.Environment{
			Account: jsii.String(os.Getenv("CDK_DEFAULT_ACCOUNT")),
			Region:  jsii.String(stacks.AWSWest.String()),
		}
	default:
		return &awscdk.Environment{
			Account: jsii.String(os.Getenv("CDK_DEFAULT_ACCOUNT")),
			Region:  jsii.String(stacks.AWSEast.String()),
		}
	}
}
