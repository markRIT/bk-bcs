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

package cluster

import "github.com/prometheus/client_golang/prometheus"

const (
	//syncStorageErr = "ZOOKEEPERErr"
	SyncSuccess = "SUCCESS"
	SyncFailure = "FAILURE"

	//actionGetData = "GetData"
	//actionWatch = "Watch"

	DataTypeApp       = "Application"
	DataTypeTaskGroup = "TaskGroup"
	DataTypeCfg       = "Configmap"
	//DataTypeSecret    = "Secret"
	DataTypeDeploy = "Deployment"
	DataTypeSvr    = "Service"
	DataTypeExpSVR = "ExportService"
)

var (
	SyncTotal = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: "bkbcs_datawatch",
		Subsystem: "mesos",
		Name:      "sync_total",
		Help:      "The total number of data sync event.",
	}, []string{"datatype", "action", "status"})
)

func init() {
	//add golang basic metrics
	prometheus.MustRegister(SyncTotal)
}
