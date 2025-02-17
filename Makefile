# BlueKing Container System Makefile
# default config
MAKE:=make
bcs_edition?=inner_edition

# init the build information
ifdef HASTAG
	GITTAG=$(shell git describe --tags)
else
	GITTAG=$(shell git describe --always)
endif

BUILDTIME = $(shell date +%Y-%m-%dT%T%z)
GITHASH=$(shell git rev-parse HEAD)
VERSION=${GITTAG}-$(shell date +%y.%m.%d)

LDFLAG=-ldflags "-X bk-bcs/bcs-common/common/static.ZookeeperClientUser=${bcs_zk_client_user} \
 -X bk-bcs/bcs-common/common/static.ZookeeperClientPwd=${bcs_zk_client_pwd} \
 -X bk-bcs/bcs-common/common/static.EncryptionKey=${bcs_encryption_key} \
 -X bk-bcs/bcs-common/common/static.ServerCertPwd=${bcs_server_cert_pwd} \
 -X bk-bcs/bcs-common/common/static.ClientCertPwd=${bcs_client_cert_pwd} \
 -X bk-bcs/bcs-common/common/static.LicenseServerClientCertPwd=${bcs_license_server_client_cert_pwd} \
 -X bk-bcs/bcs-common/common/static.BcsDefaultUser=${bcs_registry_default_user} \
 -X bk-bcs/bcs-common/common/static.BcsDefaultPasswd=${bcs_registry_default_pwd} \
 -X bk-bcs/bcs-common/common/version.BcsVersion=${VERSION} \
 -X bk-bcs/bcs-common/common/version.BcsBuildTime=${BUILDTIME} \
 -X bk-bcs/bcs-common/common/version.BcsGitHash=${GITHASH} \
 -X bk-bcs/bcs-common/common/version.BcsTag=${GITTAG} \
 -X bk-bcs/bcs-common/common/version.BcsEdition=${bcs_edition}"

# build path config
PACKAGEPATH=./build/bcs.${VERSION}
EXPORTPATH=./build/api_export

# options
default:api dns health client storage check executor mesos-driver mesos-watch scheduler loadbalance metricservice metriccollector exporter k8s-watch kube-agent k8s-driver api-export netservice sd-prometheus process-executor process-daemon bmsf-mesos-adapter hpacontroller kube-sche consoleproxy clb-controller logbeat-sidecar csi-cbs bcs-log-webhook
specific:api dns health client storage check executor mesos-driver mesos-watch scheduler loadbalance metricservice metriccollector exporter k8s-watch kube-agent k8s-driver api-export netservice sd-prometheus process-executor process-daemon bmsf-mesos-adapter hpacontroller kube-sche consoleproxy clb-controller logbeat-sidecar csi-cbs bcs-log-webhook
k8s:api client storage k8s-watch kube-agent k8s-driver csi-cbs kube-sche

allpack: svcpack k8spack mmpack mnpack
	cd build && tar -czf bcs.${VERSION}.tgz bcs.${VERSION}

# tag for different edition compiling
inner:
	$(MAKE) specific bcs_edition=inner_edition
ce:
	$(MAKE) specific bcs_edition=communication_edition
ee:
	$(MAKE) specific bcs_edition=enterprise_edition

clean:
	rm -rf ./build

svcpack:
	cd ./build/bcs.${VERSION}/bcs-services && find . -type f ! -name MD5 | xargs -L1 md5sum > MD5
	
k8spack:
	cd ./build/bcs.${VERSION}/bcs-k8s-master && find . -type f ! -name MD5 | xargs -L1 md5sum > MD5 

mmpack:
	cd ./build/bcs.${VERSION}/bcs-mesos-master && find . -type f ! -name MD5 | xargs -L1 md5sum > MD5

mnpack:
	cd ./build/bcs.${VERSION}/bcs-mesos-node && find . -type f ! -name MD5 | xargs -L1 md5sum > MD5

pre:
	@echo "git tag: ${GITTAG}"
	mkdir -p ${PACKAGEPATH}
	mkdir -p ${EXPORTPATH}
	if [ ! -d "./vendor/github.com/sirupsen" ]; then cd ./vendor/github.com && ln -sf Sirupsen sirupsen; fi
	if [ ! -d "./vendor/github.com/Sirupsen" ]; then cd ./vendor/github.com && ln -sf sirupsen Sirupsen; fi
	go fmt ./...
	cd ./scripts && chmod +x vet.sh && ./vet.sh

api:pre
	mkdir -p ${PACKAGEPATH}/bcs-services
	cp -R ./install/conf/bcs-services/bcs-api ${PACKAGEPATH}/bcs-services
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-services/bcs-api/bcs-api ./bcs-services/bcs-api/main.go

kube-agent:pre
	mkdir -p ${PACKAGEPATH}/bcs-k8s-master
	cp -R ./install/conf/bcs-k8s-master/bcs-kube-agent ${PACKAGEPATH}/bcs-k8s-master
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-k8s-master/bcs-kube-agent/bcs-kube-agent ./bcs-k8s/bcs-kube-agent/main.go

client:pre
	mkdir -p ${PACKAGEPATH}/bcs-services
	cp -R ./install/conf/bcs-services/bcs-client ${PACKAGEPATH}/bcs-services
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-services/bcs-client/bcs-client ./bcs-services/bcs-client/cmd/main.go

dns:pre
	mkdir -p ${PACKAGEPATH}/bcs-services
	mkdir -p ${PACKAGEPATH}/bcs-mesos-master
	cp -R ./install/conf/bcs-mesos-master/bcs-dns ${PACKAGEPATH}/bcs-mesos-master
	cp -R ./install/conf/bcs-services/bcs-dns-service ${PACKAGEPATH}/bcs-services
	cp bcs-services/bcs-dns/plugin.cfg vendor/github.com/coredns/coredns/
	cd vendor/github.com/coredns/coredns && make gen && cd -
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-services/bcs-dns-service/bcs-dns-service bk-bcs/vendor/github.com/coredns/coredns
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-mesos-master/bcs-dns/bcs-dns bk-bcs/vendor/github.com/coredns/coredns

health:pre
	mkdir -p ${PACKAGEPATH}/bcs-services
	cp -R ./install/conf/bcs-services/bcs-health-master ${PACKAGEPATH}/bcs-services
	cp -R ./install/conf/bcs-services/bcs-health-slave ${PACKAGEPATH}/bcs-services
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-services/bcs-health-master/bcs-health-master ./bcs-services/bcs-health/master/main.go
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-services/bcs-health-slave/bcs-health-slave ./bcs-services/bcs-health/slave/main.go

metricservice:pre
	mkdir -p ${PACKAGEPATH}/bcs-services
	cp -R ./install/conf/bcs-services/bcs-metricservice ${PACKAGEPATH}/bcs-services
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-services/bcs-metricservice/bcs-metricservice ./bcs-services/bcs-metricservice/main.go

metriccollector:pre
	mkdir -p ${PACKAGEPATH}/bcs-mesos-node
	cp -R ./install/conf/bcs-mesos-node/bcs-metriccollector ${PACKAGEPATH}/bcs-mesos-node
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-mesos-node/bcs-metriccollector/bcs-metriccollector ./bcs-services/bcs-metriccollector/main.go

exporter:pre
	mkdir -p ${PACKAGEPATH}/bcs-services
	cp -R ./install/conf/bcs-services/bcs-exporter ${PACKAGEPATH}/bcs-services
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-services/bcs-exporter/bcs-exporter ./bcs-services/bcs-exporter/main.go
	go build ${LDFLAG} -buildmode=plugin -o ${PACKAGEPATH}/bcs-services/bcs-exporter/default_exporter.so ./bcs-services/bcs-exporter/pkg/output/plugins/default_exporter/default_exporter.go
	go build ${LDFLAG} -buildmode=plugin -o ${PACKAGEPATH}/bcs-services/bcs-exporter/bkdata_exporter.so ./bcs-services/bcs-exporter/pkg/output/plugins/bkdata_exporter/

storage:pre
	mkdir -p ${PACKAGEPATH}/bcs-services
	cp -R ./install/conf/bcs-services/bcs-storage ${PACKAGEPATH}/bcs-services
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-services/bcs-storage/bcs-storage ./bcs-services/bcs-storage/storage.go

loadbalance:pre
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-services/bcs-loadbalance/bcs-loadbalance ./bcs-services/bcs-loadbalance/main.go
	cp -r ./bcs-services/bcs-loadbalance/image/* ${PACKAGEPATH}/bcs-services/bcs-loadbalance/

check:pre
	mkdir -p ${PACKAGEPATH}/bcs-mesos-master
	cp -R ./install/conf/bcs-mesos-master/bcs-check ${PACKAGEPATH}/bcs-mesos-master
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-mesos-master/bcs-check/bcs-check ./bcs-mesos/bcs-check/bcs-check.go

executor:pre
	mkdir -p ${PACKAGEPATH}/bcs-mesos-node
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-mesos-node/bcs-container-executor/bcs-container-executor ./bcs-mesos/bcs-container-executor/main.go

process-executor:pre
	mkdir -p ${PACKAGEPATH}/bcs-mesos-node
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-mesos-node/bcs-process-executor/bcs-process-executor ./bcs-mesos/bcs-process-executor/main.go

process-daemon:pre
	mkdir -p ${PACKAGEPATH}/bcs-mesos-node
	cp -R ./install/conf/bcs-mesos-node/bcs-process-daemon ${PACKAGEPATH}/bcs-mesos-node
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-mesos-node/bcs-process-daemon/bcs-process-daemon ./bcs-mesos/bcs-process-daemon/main.go

netservice:pre
	mkdir -p ${PACKAGEPATH}/bcs-services
	cp -R ./install/conf/bcs-services/bcs-netservice ${PACKAGEPATH}/bcs-services
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-services/bcs-netservice/bcs-netservice ./bcs-services/bcs-netservice/main.go
	
	mkdir -p ${PACKAGEPATH}/bcs-mesos-master
	cp -R ./install/conf/bcs-mesos-master/bcs-netservice ${PACKAGEPATH}/bcs-mesos-master
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-mesos-master/bcs-netservice/bcs-netservice ./bcs-services/bcs-netservice/main.go

	mkdir -p ${PACKAGEPATH}/bcs-mesos-node/bcs-cni/bin/conf
	mkdir -p ${PACKAGEPATH}/bcs-mesos-node/bcs-cni/conf
	cp -R ./install/conf/bcs-mesos-node/bcs-ipam/bcs.conf.template ${PACKAGEPATH}/bcs-mesos-node/bcs-cni/bin/conf
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-mesos-node/bcs-cni/bin/bcs-ipam ./bcs-services/bcs-netservice/bcs-ipam/main.go

mesos-driver:pre
	mkdir -p ${PACKAGEPATH}/bcs-mesos-master
	cp -R ./install/conf/bcs-mesos-master/bcs-mesos-driver ${PACKAGEPATH}/bcs-mesos-master
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-mesos-master/bcs-mesos-driver/bcs-mesos-driver ./bcs-mesos/bcs-mesos-driver/main.go

mesos-watch:pre
	mkdir -p ${PACKAGEPATH}/bcs-mesos-master
	cp -R ./install/conf/bcs-mesos-master/bcs-mesos-watch ${PACKAGEPATH}/bcs-mesos-master
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-mesos-master/bcs-mesos-watch/bcs-mesos-watch ./bcs-mesos/bcs-mesos-watch/main.go

kube-sche:pre
	mkdir -p ${PACKAGEPATH}/bcs-k8s-master
	cp -R ./install/conf/bcs-k8s-master/bcs-k8s-custom-scheduler ${PACKAGEPATH}/bcs-k8s-master
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-k8s-master/bcs-k8s-custom-scheduler/bcs-k8s-custom-scheduler ./bcs-k8s/bcs-k8s-custom-scheduler/main.go

csi-cbs:pre
	mkdir -p ${PACKAGEPATH}/bcs-k8s-master
	cp -R ./install/conf/bcs-k8s-master/bcs-k8s-csi-tencentcloud ${PACKAGEPATH}/bcs-k8s-master
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-k8s-master/bcs-k8s-csi-tencentcloud/bcs-k8s-csi-tencentcloud ./bcs-k8s/bcs-k8s-csi-tencentcloud/cmd/cbs/main.go

scheduler:pre
	mkdir -p ${PACKAGEPATH}/bcs-mesos-master
	cp -R ./install/conf/bcs-mesos-master/bcs-scheduler ${PACKAGEPATH}/bcs-mesos-master
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-mesos-master/bcs-scheduler/bcs-scheduler ./bcs-mesos/bcs-scheduler
	go build -buildmode=plugin -o ${PACKAGEPATH}/bcs-mesos-master/bcs-scheduler/plugin/bin/ip-resources/ip-resources.so ./bcs-mesos/bcs-scheduler/src/plugin/bin/ip-resources/ipResource.go

logbeat-sidecar:pre
	mkdir -p ${PACKAGEPATH}/bcs-services
	cp -R ./install/conf/bcs-services/bcs-logbeat-sidecar ${PACKAGEPATH}/bcs-services
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-logbeat-sidecar/bcs-logbeat-sidecar ./bcs-services/bcs-logbeat-sidecar/main.go

hpacontroller:pre
	mkdir -p ${PACKAGEPATH}/bcs-mesos-master
	cp -R ./install/conf/bcs-mesos-master/bcs-hpacontroller ${PACKAGEPATH}/bcs-mesos-master
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-mesos-master/bcs-hpacontroller/bcs-hpacontroller ./bcs-mesos/bcs-hpacontroller

sd-prometheus:pre
	mkdir -p ${PACKAGEPATH}/bcs-services
	cp -R ./install/conf/bcs-services/bcs-service-prometheus-service ${PACKAGEPATH}/bcs-services
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-services/bcs-service-prometheus-service/bcs-service-prometheus ./bcs-services/bcs-sd-prometheus/main.go

k8s-driver:pre
	mkdir -p ${PACKAGEPATH}/bcs-k8s-master
	cp -R ./install/conf/bcs-k8s-master/bcs-k8s-driver ${PACKAGEPATH}/bcs-k8s-master
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-k8s-master/bcs-k8s-driver/bcs-k8s-driver ./bcs-k8s/bcs-k8s-driver/main.go

k8s-watch:pre
	mkdir -p ${PACKAGEPATH}/bcs-k8s-master
	cp -R ./install/conf/bcs-k8s-master/bcs-k8s-watch ${PACKAGEPATH}/bcs-k8s-master
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-k8s-master/bcs-k8s-watch/bcs-k8s-watch ./bcs-k8s/bcs-k8s-watch/main.go

api-export:pre
	mkdir -p ${EXPORTPATH}
	cp ./bcs-common/common/types/meta.go ${EXPORTPATH}
	cp ./bcs-common/common/types/status.go ${EXPORTPATH}
	cp ./bcs-common/common/types/secret.go ${EXPORTPATH}
	cp ./bcs-common/common/types/configmap.go ${EXPORTPATH}

consoleproxy:pre
	mkdir -p ${PACKAGEPATH}/bcs-mesos-node
	cp -R ./install/conf/bcs-mesos-node/bcs-consoleproxy ${PACKAGEPATH}/bcs-k8s-node
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-mesos-node/bcs-consoleproxy/bcs-consoleproxy ./bcs-mesos/bcs-consoleproxy/main.go

bmsf-mesos-adapter:pre
	mkdir -p ${PACKAGEPATH}/bcs-mesos-master
	cp -R ./install/conf/bcs-mesos-master/bmsf-mesos-adapter ${PACKAGEPATH}/bcs-mesos-master
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-mesos-master/bmsf-mesos-adapter/bmsf-mesos-adapter ./bmsf-mesh/bmsf-mesos-adapter/main.go

network:pre
	mkdir -p ${PACKAGEPATH}/bcs-mesos-node/bcs-cni/bin
	mkdir -p ${PACKAGEPATH}/bcs-mesos-node/bcs-cni/conf
	cp ./install/conf/bcs-mesos-node/qcloud-eip/* ${PACKAGEPATH}/bcs-mesos-node/bcs-cni/conf
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-mesos-node/bcs-cni/bin/qcloud-eip ./bcs-services/bcs-network/qcloud-eip/main.go

clb-controller:pre
	mkdir -p ${PACKAGEPATH}/bcs-mesos-master
	GOOS=linux go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-mesos-master/bcs-clb-controller/bcs-clb-controller ./bcs-services/bcs-clb-controller/main.go

bcs-log-webhook:pre
	mkdir -p ${PACKAGEPATH}/bcs-services
	go build ${LDFLAG} -o ${PACKAGEPATH}/bcs-services/bcs-log-webhook-server/bcs-log-webhook-server ./bcs-services/bcs-log-webhook-server/main.go
