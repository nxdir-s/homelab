package iac

import (
	"github.com/aws/aws-cdk-go/awscdk/v2"
	"github.com/aws/constructs-go/constructs/v10"
	"github.com/aws/jsii-runtime-go"
)

type InfrastructureStackProps struct {
	props awscdk.StackProps
}

func NewInfrastructureStack(scope constructs.Construct, id string, props *InfrastructureStackProps) awscdk.Stack {
	var sprops awscdk.StackProps
	if props != nil {
		sprops = props.props
	}
	stack := awscdk.NewStack(scope, &id, &sprops)

	return stack
}

func main() {
	defer jsii.Close()

	app := awscdk.NewApp(nil)

	NewInfrastructureStack(app, "Infrastructure", &InfrastructureStackProps{})

	app.Synth(nil)
}
