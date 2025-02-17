package main

import (
	"example.com/cdk8s/imports/k8s"
	"example.com/cdk8s/storage"

	"github.com/aws/constructs-go/constructs/v10"
	"github.com/aws/jsii-runtime-go"
	"github.com/cdk8s-team/cdk8s-core-go/cdk8s/v2"
)

type DevChartProps struct {
	cdk8s.ChartProps
}

func NewDevStack(scope constructs.Construct, id string, props *DevChartProps) cdk8s.Chart {
	var cprops cdk8s.ChartProps
	if props != nil {
		cprops = props.ChartProps
	}
	chart := cdk8s.NewChart(scope, jsii.String(id), &cprops)

	namespaceChart := cdk8s.NewChart(scope, jsii.String(id+"-namespace"), &cprops)
	namespace := k8s.NewKubeNamespace(namespaceChart, jsii.String(id), &k8s.KubeNamespaceProps{
		Metadata: &k8s.ObjectMeta{
			Name: jsii.String(id),
		},
	})

	storageChart := cdk8s.NewChart(scope, jsii.String(id+"-storage"), &cprops)
	storageChart.AddDependency(namespaceChart)

	storage.NewPostgresCluster(storageChart, jsii.String(id+"-database"), &storage.PostgresProps{
		Namespace: namespace,
	})

	chart.AddDependency(namespaceChart)
	chart.AddDependency(storageChart)

	storage.NewPgAdmin(chart, jsii.String("pgadmin"), &storage.PgAdminProps{
		Namespace: namespace,
	})

	return chart
}

func main() {
	app := cdk8s.NewApp(nil)

	NewDevStack(app, "dev", nil)

	app.Synth()
}
