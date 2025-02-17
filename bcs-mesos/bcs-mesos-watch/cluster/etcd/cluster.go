/*
 * Tencent is pleased to support the open source community by making Blueking Container Service available.
 * Copyright (C) 2019 THL A29 Limited, a Tencent company. All rights reserved.
 * Licensed under the MIT License (the "License"); you may not use this file except
 * in compliance with the License. You may obtain a copy of the License at
 * http://opensource.org/licenses/MIT
 * Unless required by applicable law or agreed to in writing, software distributed under
 * the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
 * either express or implied. See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

package etcd

import (
	"fmt"

	"math/rand"
	"strconv"
	"time"

	"bk-bcs/bcs-common/common/blog"
	commtypes "bk-bcs/bcs-common/common/types"
	"bk-bcs/bcs-mesos/bcs-mesos-watch/cluster"
	"bk-bcs/bcs-mesos/bcs-mesos-watch/storage"
	"bk-bcs/bcs-mesos/bcs-mesos-watch/types"
	schedtypes "bk-bcs/bcs-mesos/bcs-scheduler/src/types"
	"bk-bcs/bcs-mesos/pkg/client/informers"
	"bk-bcs/bcs-mesos/pkg/client/internalclientset"

	"golang.org/x/net/context"
	"k8s.io/client-go/tools/clientcmd"
)

var (
	//ApplicationThreadNum goroutine number for Application channel
	ApplicationThreadNum int
	//TaskgroupThreadNum goroutine number for taskgroup channel
	TaskgroupThreadNum int
	//ExportserviceThreadNum goroutine number for exportservice channel
	ExportserviceThreadNum int
)

//NewEtcdCluster create mesos cluster
func NewEtcdCluster(cfg *types.CmdConfig, st storage.Storage) cluster.Cluster {
	blog.Info("etcd cluster(%s) will be created ...", cfg.ClusterID)

	ApplicationThreadNum = cfg.ApplicationThreadNum
	TaskgroupThreadNum = cfg.TaskgroupThreadNum
	ExportserviceThreadNum = cfg.ExportserviceThreadNum

	mesos := &EtcdCluster{
		kubeconfig:     cfg.KubeConfig,
		clusterID:      cfg.ClusterID,
		storage:        st,
		reportCallback: make(map[string]cluster.ReportFunc),
		existCallback:  make(map[string]cluster.DataExister),
	}

	//mesos watch initialize
	if err := mesos.initialize(); err != nil {
		blog.Error("etcd cluster initialize failed, %s", err.Error())
		return nil
	}
	return mesos
}

//EtcdCluster cluster implements all cluster interface
type EtcdCluster struct {
	kubeconfig     string
	factory        informers.SharedInformerFactory
	clusterID      string                         //watch cluster id
	connCxt        context.Context                //context for client disconnected
	cancel         context.CancelFunc             //cancel func when client disconnected
	reportCallback map[string]cluster.ReportFunc  //report map for handling registery data type
	existCallback  map[string]cluster.DataExister //check data exist in local cache
	storage        storage.Storage                //storage interface for remote Storage, like CC
	app            *AppWatch                      //watch for application
	taskGroup      *TaskGroupWatch                //watch for taskgroup
	exportSvr      *ExportServiceWatch            //watch for exportservice
	Status         string                         //curr status
	configmap      *ConfigMapWatch
	secret         *SecretWatch
	service        *ServiceWatch
	deployment     *DeploymentWatch
	endpoint       *EndpointWatch
	stopCh         chan struct{}
}

// GenerateRandnum just for test
func GenerateRandnum() int {
	rand.Seed(time.Now().Unix())
	rnd := rand.Intn(100)
	return rnd
}

func (ms *EtcdCluster) registerReportHandler() error {

	blog.Info("mesos cluster register report handler...")

	ms.reportCallback["Application"] = ms.reportApplication
	for i := 0; i == 0 || i < ApplicationThreadNum; i++ {
		applicationChannel := types.ApplicationChannelPrefix + strconv.Itoa(i)
		ms.reportCallback[applicationChannel] = ms.reportApplication
	}

	ms.reportCallback["TaskGroup"] = ms.reportTaskGroup
	for i := 0; i == 0 || i < TaskgroupThreadNum; i++ {
		taskGroupChannel := types.TaskgroupChannelPrefix + strconv.Itoa(i)
		ms.reportCallback[taskGroupChannel] = ms.reportTaskGroup
	}

	ms.reportCallback["ExportService"] = ms.reportExportService
	for i := 0; i == 0 || i < ExportserviceThreadNum; i++ {
		exportserviceChannel := types.ExportserviceChannelPrefix + strconv.Itoa(i)
		ms.reportCallback[exportserviceChannel] = ms.reportExportService
	}

	ms.reportCallback["ConfigMap"] = ms.reportConfigMap
	ms.reportCallback["Service"] = ms.reportService
	ms.reportCallback["Secret"] = ms.reportSecret

	ms.reportCallback["Deployment"] = ms.reportDeployment

	ms.reportCallback["Endpoint"] = ms.reportEndpoint

	return nil
}

func (ms *EtcdCluster) createDatTypeWatch() error {

	blog.Info("mesos cluster create exportservice watcher...")
	epSvrCxt, _ := context.WithCancel(ms.connCxt)
	ms.exportSvr = NewExportServiceWatch(epSvrCxt, ms.factory, ms, ms.clusterID)

	blog.Info("mesos cluster create taskgroup watcher...")
	taskCxt, _ := context.WithCancel(ms.connCxt)
	ms.taskGroup = NewTaskGroupWatch(taskCxt, ms.factory.Bkbcs().V2().TaskGroups(), ms)
	go ms.taskGroup.Work()

	blog.Info("mesos cluster create app watcher...")
	appCxt, _ := context.WithCancel(ms.connCxt)
	ms.app = NewAppWatch(appCxt, ms.factory.Bkbcs().V2().Applications(), ms)
	go ms.app.Work()

	configmapCxt, _ := context.WithCancel(ms.connCxt)
	ms.configmap = NewConfigMapWatch(configmapCxt, ms.factory.Bkbcs().V2().BcsConfigMaps(), ms)
	go ms.configmap.Work()

	secretCxt, _ := context.WithCancel(ms.connCxt)
	ms.secret = NewSecretWatch(secretCxt, ms.factory.Bkbcs().V2().BcsSecrets(), ms)
	go ms.secret.Work()

	serviceCxt, _ := context.WithCancel(ms.connCxt)
	ms.service = NewServiceWatch(serviceCxt, ms.factory.Bkbcs().V2().BcsServices(), ms)
	go ms.service.Work()

	deploymentCxt, _ := context.WithCancel(ms.connCxt)
	ms.deployment = NewDeploymentWatch(deploymentCxt, ms.factory.Bkbcs().V2().Deployments(), ms)
	go ms.deployment.Work()

	endpointCxt, _ := context.WithCancel(ms.connCxt)
	ms.endpoint = NewEndpointWatch(endpointCxt, ms.factory.Bkbcs().V2().BcsEndpoints(), ms)
	go ms.endpoint.Work()

	return nil
}

func (ms *EtcdCluster) initialize() error {

	blog.Info("EtcdCluster(%s) initialize ...", ms.clusterID)

	restConfig, err := clientcmd.BuildConfigFromFlags("", ms.kubeconfig)
	if err != nil {
		blog.Errorf("EtcdCluster build kubeconfig %s error %s", ms.kubeconfig, err.Error())
		return err
	}
	blog.Infof("EtcdCluster build kubeconfig %s success", ms.kubeconfig)

	bkbcsClientset, err := internalclientset.NewForConfig(restConfig)
	if err != nil {
		blog.Errorf("EtcdCluster build clientset error %s", err.Error())
		return err
	}

	ms.stopCh = make(chan struct{})
	factory := informers.NewSharedInformerFactory(bkbcsClientset, time.Minute*5)
	ms.factory = factory
	//init factory informers
	ms.factory.Bkbcs().V2().BcsConfigMaps().Informer()
	ms.factory.Bkbcs().V2().Applications().Informer()
	ms.factory.Bkbcs().V2().Deployments().Informer()
	ms.factory.Bkbcs().V2().BcsSecrets().Informer()
	ms.factory.Bkbcs().V2().BcsServices().Informer()
	ms.factory.Bkbcs().V2().TaskGroups().Informer()
	ms.factory.Bkbcs().V2().BcsEndpoints().Informer()

	blog.Infof("EtcdCluster SharedInformerFactory start...")
	ms.factory.Start(ms.stopCh)
	// Wait for all caches to sync.
	ms.factory.WaitForCacheSync(ms.stopCh)
	blog.Infof("EtcdCluster SharedInformerFactory sync data to cache done")

	//register ReporterHandler
	if err := ms.registerReportHandler(); err != nil {

		blog.Error("Mesos cluster register report handler err:%s", err.Error())
		return err
	}

	ms.connCxt, ms.cancel = context.WithCancel(context.Background())
	//create datatype watch
	if err := ms.createDatTypeWatch(); err != nil {
		blog.Error("Mesos cluster create wathers err:%s", err.Error())
		return err
	}

	ms.Status = "running"

	return nil
}

//ReportData report data to reportHandler, handle all data independently
func (ms *EtcdCluster) ReportData(data *types.BcsSyncData) error {
	callBack, ok := ms.reportCallback[data.DataType]
	if !ok {
		blog.Error("ReportHandler for %s do not register", data.DataType)
		return fmt.Errorf("ReportHandler for %s do not register", data.DataType)
	}
	return callBack(data)
}

func (ms *EtcdCluster) reportService(data *types.BcsSyncData) error {
	dataType := data.Item.(*commtypes.BcsService)
	blog.V(3).Infof("mesos cluster report service(%s.%s) for action(%s)",
		dataType.ObjectMeta.NameSpace, dataType.ObjectMeta.Name, data.Action)

	ms.exportSvr.postData(data)
	if err := ms.storage.Sync(data); err != nil {
		blog.Error("service(%s.%s) sync(%s) dispatch failed: %+v",
			dataType.ObjectMeta.NameSpace, dataType.ObjectMeta.Name, data.Action, err)
		return err
	}
	return nil
}

func (ms *EtcdCluster) reportConfigMap(data *types.BcsSyncData) error {
	dataType := data.Item.(*commtypes.BcsConfigMap)
	blog.V(3).Infof("mesos cluster report configmap(%s.%s) for action(%s)",
		dataType.ObjectMeta.NameSpace, dataType.ObjectMeta.Name, data.Action)
	if err := ms.storage.Sync(data); err != nil {
		blog.Error("configmap(%s.%s) sync(%s) dispatch failed: %+v",
			dataType.ObjectMeta.NameSpace, dataType.ObjectMeta.Name, data.Action, err)
		return err
	}
	return nil
}

func (ms *EtcdCluster) reportDeployment(data *types.BcsSyncData) error {
	dataType := data.Item.(*schedtypes.Deployment)
	blog.V(3).Infof("mesos cluster report deployment(%s.%s) for action(%s)",
		dataType.ObjectMeta.NameSpace, dataType.ObjectMeta.Name, data.Action)
	if err := ms.storage.Sync(data); err != nil {
		blog.Error("deployment(%s.%s) sync(%s) dispatch failed: %+v",
			dataType.ObjectMeta.NameSpace, dataType.ObjectMeta.Name, data.Action, err)
		return err
	}
	return nil
}

func (ms *EtcdCluster) reportSecret(data *types.BcsSyncData) error {
	dataType := data.Item.(*commtypes.BcsSecret)
	blog.V(3).Infof("mesos cluster report secret(%s.%s) for action(%s)",
		dataType.ObjectMeta.NameSpace, dataType.ObjectMeta.Name, data.Action)
	if err := ms.storage.Sync(data); err != nil {
		blog.Error("secret(%s.%s) sync(%s) dispatch failed: %+v",
			dataType.ObjectMeta.NameSpace, dataType.ObjectMeta.Name, data.Action, err)
		return err
	}
	return nil
}

func (ms *EtcdCluster) reportEndpoint(data *types.BcsSyncData) error {
	dataType := data.Item.(*commtypes.BcsEndpoint)
	blog.V(3).Infof("mesos cluster report endpoint(%s.%s) for action(%s)",
		dataType.ObjectMeta.NameSpace, dataType.ObjectMeta.Name, data.Action)
	if err := ms.storage.Sync(data); err != nil {
		blog.Error("endpoint(%s.%s) sync(%s) dispatch failed: %+v",
			dataType.ObjectMeta.NameSpace, dataType.ObjectMeta.Name, data.Action, err)
		return err
	}
	return nil
}

//reportTaskGroup
func (ms *EtcdCluster) reportTaskGroup(data *types.BcsSyncData) error {

	taskgroup := data.Item.(*schedtypes.TaskGroup)
	blog.V(3).Infof("mesos cluster report taskgroup(%s) for action(%s)", taskgroup.ID, data.Action)

	//post to ExportService first
	ms.exportSvr.postData(data)
	if err := ms.storage.Sync(data); err != nil {
		blog.Error("TaskGroup sync dispatch failed: %+v", err)
		return err
	}
	return nil
}

//reportApplication
func (ms *EtcdCluster) reportApplication(data *types.BcsSyncData) error {

	app := data.Item.(*schedtypes.Application)
	blog.V(3).Infof("mesos cluster report app(%s %s) for action(%s)", app.RunAs, app.ID, data.Action)

	if err := ms.storage.Sync(data); err != nil {
		blog.Error("Application sync dispatch failed: %+v", err)
		return err
	}
	return nil
}

//reportExportService
func (ms *EtcdCluster) reportExportService(data *types.BcsSyncData) error {

	blog.V(3).Infof("mesos cluster report service for action(%s)", data.Action)

	if err := ms.storage.Sync(data); err != nil {
		blog.Error("ExportService sync dispatch failed: %+v", err)
		return err
	}
	return nil
}

//Run running cluster watch
func (ms *EtcdCluster) Run(cxt context.Context) {
	blog.Info("etcd cluster run ...")
}

//Sync ask cluster to sync data to local cache
func (ms *EtcdCluster) Sync(tp string) error {
	blog.Info("etcd cluster sync ...")
	return nil
}

//Stop ask cluster stopped
func (ms *EtcdCluster) Stop() {
	blog.Info("etcd cluster stop ...")
	blog.Info("EtcdCluster stop exportsvr watcher...")
	ms.exportSvr.stop()
	if ms.cancel != nil {
		ms.cancel()
	}
	close(ms.stopCh)
	time.Sleep(2 * time.Second)
}

//GetClusterStatus get synchronization status
func (ms *EtcdCluster) GetClusterStatus() string {
	return ms.Status
}
