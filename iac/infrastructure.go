package iac

import (
	"os"

	"github.com/aws/aws-cdk-go/awscdk/v2"
	ec2 "github.com/aws/aws-cdk-go/awscdk/v2/awsec2"
	ecs "github.com/aws/aws-cdk-go/awscdk/v2/awsecs"
	elb "github.com/aws/aws-cdk-go/awscdk/v2/awselasticloadbalancingv2"
	"github.com/aws/constructs-go/constructs/v10"
	"github.com/aws/jsii-runtime-go"

	"github.com/nxdir-s/homelab/iac/stacks"
)

const (
	AppName string = "webserver"

	OtelServiceDev  string = AppName + "-dev"
	OtelServiceProd string = AppName

	FargateServiceName              string = AppName + "-fargate-service"
	FargateDesiredCount             int    = 1
	FargateCapacityProvidersEnabled bool   = true
	FargateCpu                      int    = 4096

	LatestImage string = "latest"

	BlueTGName  string = "alb-blue-tg"
	GreenTGName string = "alb-green-tg"

	VpcIpAddresses string = "10.45.0.0/16"
	TcpPort        int    = 80

	AlbOpen   bool = false
	AlbPublic bool = true

	SgDescription      string = "Allows access on port 80/http"
	AllowOutboundRules bool   = true

	DefaultRemoteRule bool = false

	AccountEnvKey string = "CDK_DEFAULT_ACCOUNT"
	RegionEnvKey  string = "CDK_DEFAULT_REGION"

	PipelineName string = AppName + "-pipeline"
)

type InfrastructureStackProps struct {
	props   awscdk.StackProps
	enabled bool
	name    string
}

func NewInfrastructureStack(scope constructs.Construct, id string, props *InfrastructureStackProps) awscdk.Stack {
	var sprops awscdk.StackProps
	if props != nil {
		sprops = props.props
	}
	stack := awscdk.NewStack(scope, &id, &sprops)

	vpc := ec2.Vpc_FromLookup(stack, jsii.String("vpc"), &ec2.VpcLookupOptions{
		IsDefault: jsii.Bool(true),
	})

	targetGroupBlue := stacks.NewTargetGroup(stack, id+"TGB", &stacks.TargetGroupProps{
		Name:       BlueTGName,
		TargetType: elb.TargetType_IP,
		Vpc:        vpc,
		Port:       TcpPort,
	})

	targetGroupGreen := stacks.NewTargetGroup(stack, id+"TGG", &stacks.TargetGroupProps{
		Name:       GreenTGName,
		TargetType: elb.TargetType_IP,
		Vpc:        vpc,
		Port:       TcpPort,
	})

	// Creates an Elastic Container Registry (ECR) image repository
	imageRepo := stacks.NewEcrRepository(stack, id+"Image", &stacks.EcrRepositoryProps{
		RemovalPolicy: awscdk.RemovalPolicy_DESTROY,
	})

	ecsCluster := stacks.NewEcsCluster(stack, id+"Cluster", &stacks.EcsClusterProps{
		Vpc:                            vpc,
		EnableFargateCapacityProviders: FargateCapacityProvidersEnabled,
	})

	logDriver := stacks.NewLogDriver(stack, &stacks.LogDriverProps{
		StreamPrefix: id + "Container",
		Mode:         ecs.AwsLogDriverMode_NON_BLOCKING,
	})

	taskDef := stacks.NewFargateTaskDefinition(stack, id+"Def", &stacks.FargateTaskDefinitionProps{
		ImageRepo:     imageRepo,
		ImageTag:      LatestImage,
		ContainerName: id + "Container",
		Port:          TcpPort,
		LogDriver:     logDriver,
		Cpu:           FargateCpu,
		PidMode:       ecs.PidMode_TASK,
		RuntimePlatform: &ecs.RuntimePlatform{
			OperatingSystemFamily: ecs.OperatingSystemFamily_LINUX(),
			CpuArchitecture:       ecs.CpuArchitecture_ARM64(),
		},
	})

	fargateService := stacks.NewFargateService(stack, id+"Serv", &stacks.FargateServiceProps{
		ServiceName:    FargateServiceName,
		DesiredCount:   FargateDesiredCount,
		TaskDefinition: taskDef,
		Vpc:            vpc,
		Cluster:        ecsCluster,
		// Sets CodeDeploy as the deployment controller
		DeploymentController: &ecs.DeploymentController{
			Type: ecs.DeploymentControllerType_CODE_DEPLOY,
		},
	})

	// Adds the ECS Fargate service to the ALB target group
	fargateService.AttachToApplicationTargetGroup(targetGroupBlue)

	// Creates a Security Group for the Application Load Balancer (ALB)
	albSg := stacks.NewAlbSecurityGroup(stack, id+"SG", &stacks.SecurityGroupProps{
		Vpc:           vpc,
		Port:          TcpPort,
		AllowOutbound: AllowOutboundRules,
		RemoteRule:    DefaultRemoteRule,
		Description:   SgDescription,
	})

	publicAlb := stacks.NewAlb(stack, id+"Alb", &stacks.AlbProps{
		Vpc:            vpc,
		SecurityGroups: albSg,
		InternetFacing: AlbPublic,
	})

	// Adds a listener on port 80 to the ALB
	albListener := publicAlb.AddListener(jsii.String(id+"Listener"), &elb.BaseApplicationListenerProps{
		Port: jsii.Number(TcpPort),
		Open: jsii.Bool(AlbOpen),
		DefaultTargetGroups: &[]elb.IApplicationTargetGroup{
			targetGroupBlue,
		},
	})

	stacks.NewDeployPipelineStack(stack, id+"Pipeline", &stacks.PipelineNestedStackProps{
		PipelineName:   PipelineName,
		AppName:        props.name,
		FargateService: fargateService,
		TaskDefinition: taskDef,
		Repository:     imageRepo,
		Vpc:            vpc,
		LoadBalancer:   publicAlb,
		Listener:       albListener,
		TargetGroupB:   targetGroupBlue,
		TargetGroupG:   targetGroupGreen,
	})

	return stack
}

func main() {
	defer jsii.Close()

	app := awscdk.NewApp(nil)

	NewInfrastructureStack(app, "WebInfrastructure", &InfrastructureStackProps{
		props: awscdk.StackProps{
			Synthesizer: awscdk.NewDefaultStackSynthesizer(&awscdk.DefaultStackSynthesizerProps{}),
			Env:         env(stacks.DevEast),
		},
		name:    AppName,
		enabled: true,
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
