package storage

import (
	"example.com/cdk8s/imports/k8s"
	"github.com/aws/constructs-go/constructs/v10"
	"github.com/aws/jsii-runtime-go"
)

const (
	PgAdminPort          float64 = 5430
	PgAdminContainerPort float64 = 80
	PgAdminImage         string  = "dpage/pgadmin4"
)

type PgAdminProps struct {
	Namespace k8s.KubeNamespace
	Port      *float64
	Image     *string
}

func NewPgAdmin(scope constructs.Construct, id *string, props *PgAdminProps) constructs.Construct {
	pgAdmin := constructs.NewConstruct(scope, id)

	port := props.Port
	if port == nil {
		port = jsii.Number(PgAdminPort)
	}

	image := props.Image
	if image == nil {
		image = jsii.String(PgAdminImage)
	}

	label := map[string]*string{"app": id}

	service := k8s.NewKubeService(pgAdmin, jsii.String(*id+"-service"), &k8s.KubeServiceProps{
		Metadata: &k8s.ObjectMeta{
			Name:      id,
			Namespace: props.Namespace.Name(),
		},
		Spec: &k8s.ServiceSpec{
			Type:     jsii.String("LoadBalancer"),
			Selector: &label,
			Ports: &[]*k8s.ServicePort{
				{
					Port:       port,
					TargetPort: k8s.IntOrString_FromNumber(jsii.Number(PgAdminContainerPort)),
				},
			},
		},
	})

	deployment := k8s.NewKubeDeployment(pgAdmin, id, &k8s.KubeDeploymentProps{
		Metadata: &k8s.ObjectMeta{
			Name:      jsii.String(*id + "-deployment"),
			Namespace: props.Namespace.Name(),
		},
		Spec: &k8s.DeploymentSpec{
			Replicas: jsii.Number(1),
			Selector: &k8s.LabelSelector{
				MatchLabels: &label,
			},
			Template: &k8s.PodTemplateSpec{
				Metadata: &k8s.ObjectMeta{
					Name:      id,
					Labels:    &label,
					Namespace: props.Namespace.Name(),
				},
				Spec: &k8s.PodSpec{
					RestartPolicy: jsii.String("Always"),
					Containers: &[]*k8s.Container{
						{
							Name:            id,
							Image:           image,
							ImagePullPolicy: jsii.String("Always"),
							Ports: &[]*k8s.ContainerPort{
								{
									ContainerPort: jsii.Number(PgAdminContainerPort),
								},
							},
							Env: &[]*k8s.EnvVar{
								{
									Name:  jsii.String("PGADMIN_DEFAULT_EMAIL"),
									Value: jsii.String("admin@example.com"),
								},
								{
									Name:  jsii.String("PGADMIN_DEFAULT_PASSWORD"),
									Value: jsii.String("admin"),
								},
							},
						},
					},
				},
			},
		},
	})

	deployment.AddDependency(service)

	return pgAdmin
}
