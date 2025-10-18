package stacks

type BaseProps struct {
	Account string
	Region  AWSRegion
	Env     Environment
	Tags    *map[string]*string
}

type Environment string

func (s Environment) String() string {
	return string(s)
}

const (
	EnvDEV  Environment = "dev"
	EnvQA   Environment = "qa"
	EnvPROD Environment = "prod"
)

type AWSRegion string

func (s AWSRegion) String() string {
	return string(s)
}

const (
	AWSEast AWSRegion = "us-east-1"
	AWSWest AWSRegion = "us-west-2"
)

type EnvRegion string

func (s EnvRegion) String() string {
	return string(s)
}

const (
	DevEast EnvRegion = "dev-east"

	QAEast EnvRegion = "qa-east"
	QAWest EnvRegion = "qa-west"

	ProdEast EnvRegion = "prod-east"
	ProdWest EnvRegion = "prod-west"
)
