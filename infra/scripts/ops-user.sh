#!/usr/bin/env bash
# Copyright 2017 VMware, Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.!/bin/bash

set -euf -o pipefail

GOVC_URL=${GOVC_URL-""}
GOVC_DATACENTER=${GOVC_DATACENTER-""}
GOVC_INSECURE=${GOVC_INSECURE-0}

command -v govc >/dev/null 2>&1 || { echo "govc must be installed" >&2; exit 1; }

show_help() {
	echo "Usage"
	echo ""
	echo "    Create a user on vCenter with appropriate permissions for VCH deployment with --ops-user"
	echo ""
  echo "    Manual setup: https://github.com/vmware/vic/blob/08-docs/doc/user_doc/vic_installation/set_up_ops_user.md"
  echo ""
	echo "    $0 -o OPS_USERNAME -p OPS_PASSWORD -t admin_user:admin_pass@<vCenter Host> -c DATACENTER -d DATASTORE_1 -l CLUSTER -n NETWORK_1 "
  echo ""
  echo "    Values from GOVC environment variables do not need to be provided if the environment variable is set"
  echo ""
  echo "    -a Skip role creation"
  echo "    -c Datacenter (e.g. ha-datacenter) [GOVC_DATACENTER]"
  echo "    -d Datastore paths - standalone or vSAN datastores (e.g. /ha-datacenter/datastore/datastore1) (specify -e multiples times)"
  echo "    -l Cluster path to create resource pool (e.g. /ha-datacenter/host/cluster1)"
  echo "    -n Networks - vDS and DPG path (e.g. /ha-datacenter/network/vch-vds) (specify -n multiple times)"
  echo "    -o Ops user (e.g. ops@vsphere.local) (defaults to \"root\")"
  echo "    -p Ops password (defaults to \"Admin\!23\")"
  echo "    -r Host for resource pool if not clustered (e.g. /ha-datacenter/host/1.1.1.1)"
  echo "    -t Target vCenter URL (username:password@vcenter_ip) [GOVC_URL]"
  echo "    -k Skip verification of server certificate [GOVC_INSECURE]"
  echo "    -v Verbose"
}

CREATE_ROLES=1
CLUSTER_PATH=""
DATASTORE_PATHS=("")
IS_VC=0
NETWORK_PATHS=("")
OPS_USER="root"
OPS_PASSWORD="Admin!23"
RP_HOST=""
VERBOSE=0

while getopts :ac:d:hkl:n:o:p:r:t:v flag ; do
    case $flag in
				a)
            CREATE_ROLES=0
						;;
				c)
						GOVC_DATACENTER=$OPTARG
					  ;;
        d)
            DATASTORE_PATHS+=("$OPTARG")
            ;;
        h)
            show_help
            exit 1
            ;;
        k)
            GOVC_INSECURE=1
            ;;
        l)
            CLUSTER_PATH=$OPTARG
            ;;
        n)
            NETWORK_PATHS+=("$OPTARG")
            ;;
				o)
						OPS_USER=$OPTARG
						;;
				p)
						OPS_PASSWORD=$OPTARG
						;;
        r)
            RP_HOST=$OPTARG
            ;;
				t)
						GOVC_URL=$OPTARG
						;;
        v)
						VERBOSE=1
						;;
        \?)
            show_help
            exit 1
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
done

export GOVC_URL=$GOVC_URL
export GOVC_DATACENTER=$GOVC_DATACENTER
export GOVC_INSECURE=$GOVC_INSECURE


if [ "$(govc about -json | jq -r .About.ProductLineId)" == "vpx" ]; then
  IS_VC=1
  echo "Target is vCenter"
else
  echo "Target is ESXi"
fi

if [ "$VERBOSE" -eq 1 ]; then
  echo "target/url:   $GOVC_URL"
  echo "dc:           $GOVC_DATACENTER"
  echo "insecure:     $GOVC_INSECURE"
  echo "is vCenter:   $IS_VC"

  echo "cluster:      $CLUSTER_PATH"
  echo "rp host:      $RP_HOST"
  echo "datastores:   ${DATASTORE_PATHS[@]}"
  echo "networks:     ${NETWORK_PATHS[@]}"

  echo "ops user:     $OPS_USER"
  echo "ops pass:     $OPS_PASSWORD"
  echo "verbose:      $VERBOSE"
  echo "create roles: $CREATE_ROLES"
fi

# required values
if [[ -z "${NETWORK_PATHS[@]}" ]]; then
  echo "Networks (-n) must be provided"
  exit 1
fi

if [[ -z "$GOVC_DATACENTER" ]]; then
  echo "Datacenter (-c) must be provided"
  exit 1
fi

if [[ -z "$GOVC_URL" ]]; then
  echo "Target (-t) must be provided"
  exit 1
fi

if [[ -z "$OPS_USER" || -z "$OPS_PASSWORD" ]]; then
  echo "Missing ops user (-o) or ops password (-p)"
  exit 1
fi

if [[ -z "$RP_HOST" && -z "$CLUSTER_PATH" ]]; then
  echo "Resource pool host (-r) or cluster (-l) must be provided"
  exit 1
fi

if [[ -n "$RP_HOST" && -n "$CLUSTER_PATH" ]]; then
  echo "Only one of resource pool host (-r) and cluster (-l) may be provided"
  exit 1
fi

# TODO Create SSO user
# https://pubs.vmware.com/vsphere-60/index.jsp?topic=%2Fcom.vmware.vsphere.security.doc%2FGUID-72BFF98C-C530-4C50-BF31-B5779D2A4BBB.html
# Use builtin vCenter localos root user as ops user for now

VCENTER_ROLE="VCH_vcenter"
DATACENTER_ROLE="VCH_datacenter"
DATASTORE_ROLE="VCH_datastore"
NETWORK_ROLE="VCH_network"
ENDPOINT_ROLE="VCH_endpoint"
READONLY_ROLE="ReadOnly"

# Create roles with permissions
if [ "$CREATE_ROLES" -eq 1 ]; then
  echo "Creating roles"
  # FIXME Added System.* for ESX
  govc role.create $VCENTER_ROLE Datastore.Config System.Read System.Anonymous System.View
  govc role.create $DATACENTER_ROLE  Datastore.Config Datastore.FileManagement

    # Datastore.* was testing on ESX for DATASTORE_ROLE
#    Datastore.AllocateSpace \
#    Datastore.Browse \
#    Datastore.Config \
#    Datastore.Delete \
#    Datastore.DeleteFile \
#    Datastore.FileManagement \
#    Datastore.Move \
#    Datastore.Rename \
#    Datastore.UpdateVirtualMachineFiles \
#    Datastore.UpdateVirtualMachineMetadata \
  govc role.create $DATASTORE_ROLE \
    Datastore.AllocateSpace \
    Datastore.Browse \
    Datastore.Config \
    Datastore.DeleteFile \
    Datastore.FileManagement \
    Host.Config.SystemManagement \
    System.Read
  govc role.create $NETWORK_ROLE Network.Assign
  govc role.create $ENDPOINT_ROLE \
    DVPortgroup.Modify \
    DVPortgroup.PolicyOp \
    DVPortgroup.ScopeOp \
    VApp.AssignVM \
    VirtualMachine.Config.AddNewDisk \
    VirtualMachine.Config.AddRemoveDevice \
    VirtualMachine.Config.AdvancedConfig \
    VirtualMachine.Config.RemoveDisk \
    VirtualMachine.GuestOperations.Execute \
    VirtualMachine.Interact.DeviceConnection \
    VirtualMachine.Interact.PowerOff \
    VirtualMachine.Interact.PowerOn \
    VirtualMachine.Inventory.Create \
    VirtualMachine.Inventory.Delete \
    VirtualMachine.Inventory.Register \
    VirtualMachine.Inventory.Unregister

   # VirtualMachine.Config.* for testing
   #
   # VirtualMachine.Config.AddExistingDisk \
   # VirtualMachine.Config.AddNewDisk \
   # VirtualMachine.Config.AddRemoveDevice \
   # VirtualMachine.Config.AdvancedConfig \
   # VirtualMachine.Config.Annotation \
   # VirtualMachine.Config.CPUCount \
   # VirtualMachine.Config.ChangeTracking \
   # VirtualMachine.Config.DiskExtend \
   # VirtualMachine.Config.DiskLease \
   # VirtualMachine.Config.EditDevice \
   # VirtualMachine.Config.HostUSBDevice \
   # VirtualMachine.Config.ManagedBy \
   # VirtualMachine.Config.Memory \
   # VirtualMachine.Config.MksControl \
   # VirtualMachine.Config.QueryFTCompatibility \
   # VirtualMachine.Config.QueryUnownedFiles \
   # VirtualMachine.Config.RawDevice \
   # VirtualMachine.Config.ReloadFromPath \
   # VirtualMachine.Config.RemoveDisk \
   # VirtualMachine.Config.Rename \
   # VirtualMachine.Config.ResetGuestInfo \
   # VirtualMachine.Config.Resource \
   # VirtualMachine.Config.Settings \
   # VirtualMachine.Config.SwapPlacement \
   # VirtualMachine.Config.ToggleForkParent \
   # VirtualMachine.Config.Unlock \
   # VirtualMachine.Config.UpgradeVirtualHardware
else
  echo "Skipping create roles"
fi


move_network() {

  net=$(basename "$1")
  echo "Network: $net"

  set +e
  nets=$(govc ls "$DATACENTER_PATH/network" | grep "$net")
  set -e
  echo "Networks found: $nets"
  net_count=$(echo $nets | wc -l)
  if [ "$net_count" == "0" ]; then
    echo "Failed to find matching networks"
    exit 1
  fi
  # This is ghetto because xargs adds quotes when it substitutes the values
  net_mv_cmd=$(echo $nets | xargs | xargs -t -I {} echo "govc object.mv {} $NETWORK_FOLDER_PATH" | sed 's/"//g')
  echo "Network move command: $net_mv_cmd"
  if [ -z "$net_mv_cmd" ]; then
    echo "Failed to find network $net"
    exit 1
  fi
  eval $net_mv_cmd
  echo "Moved $net to $NETWORK_FOLDER_PATH"
}

# Create network folder
DATACENTER_PATH="/$GOVC_DATACENTER"

if [ "$IS_VC" == 1 ]; then
  echo "Creating network folder"
  NETWORK_FOLDER_PATH="$DATACENTER_PATH/network/VCH_networks"
  govc folder.create "$NETWORK_FOLDER_PATH"

  echo "Moving networks to the network folder"
  temp=("")
  for net in "${NETWORK_PATHS[@]}"
  do
    echo "Moving network $net"
    move_network "$net"
    if [ $? -eq 0 ]; then
      moved_path="$NETWORK_FOLDER_PATH/$net"
      temp+=("$moved_path")
    fi
  done
  # save the moved paths
  NETWORK_PATHS=temp
  echo "Moved network paths: ${NETWORK_PATHS[@]}"
else
  echo "Skipping network folder on ESX"
fi

# Create resource pool
#RP_PATH=""
if [ -n "$RP_HOST" ]; then
  RP_PATH="$RP_HOST/VCH_pool"
  govc pool.create -cpu.limit=-1 -cpu.reservation=1 -mem.limit=-1 -mem.reservation=1 "$RP_PATH"
  echo "Resource pool: $RP_PATH"
fi

# Assign roles to inventory objects
echo "Assigning roles to inventory objects"

if [ "$IS_VC" == 0 ]; then
  # On ESX we may need the equivalent of ReadOnly role with propagate true (this still doesn't work)
  govc permissions.set -principal "$OPS_USER" -role $VCENTER_ROLE -propagate=true "/"
  echo "Set $VCENTER_ROLE role on /"
else
  # top level vC instance
  govc permissions.set -principal "$OPS_USER" -role $VCENTER_ROLE -propagate=false "/"
  echo "Set $VCENTER_ROLE role on /"
fi

# datacenters
govc permissions.set -principal "$OPS_USER" -role $DATACENTER_ROLE -propagate=false "$DATACENTER_PATH"
echo "Set $DATACENTER_ROLE role on $DATACENTER_PATH"

# clusters
if [ -n "$CLUSTER_PATH" ]; then
  govc permissions.set -principal "$OPS_USER" -role $DATASTORE_ROLE -propagate=true "$CLUSTER_PATH"
  echo "Set $DATASTORE_ROLE role on $CLUSTER_PATH"
fi

# datastores
for path in "${DATASTORE_PATHS[@]}"
do
    govc permissions.set -principal "$OPS_USER" -role $DATASTORE_ROLE -propagate=false "$path"
    echo "Set $DATASTORE_ROLE role on $path"
done

# network folders
if [ "$IS_VC" == 1 ]; then
  govc permissions.set -principal "$OPS_USER" -role $READONLY_ROLE -propagate=true "$NETWORK_FOLDER_PATH"
  echo "Set ReadOnly role on $NETWORK_FOLDER_PATH"
fi

# networks
for path in "${NETWORK_PATHS[@]}"
do
  govc permissions.set -principal "$OPS_USER" -role $NETWORK_ROLE -propagate=false "$path"
  echo "Set $NETWORK_ROLE role on $path"
done

# resource pool
if [ -n "$RP_PATH" ]; then
  govc permissions.set -principal "$OPS_USER" -role $ENDPOINT_ROLE -propagate=true "$RP_PATH"
  echo "Set $ENDPOINT_ROLE role on $RP_PATH"
fi

# Apply to cluster since we're not using RP for now
if [ -n "$CLUSTER" ]; then
  govc permissions.set -principal "$OPS_USER" -role $ENDPOINT_ROLE -propagate=true "$CLUSTER_PATH"
  echo "Set $ENDPOINT_ROLE role on $CLUSTER_PATH"
fi

# vApps
#$VAPP_PATH=""
#govc permissions.set -principal "$OPS_USER" -role $ENDPOINT_ROLE -propagate=true "$VAPP_PATH"
#echo "Set $ENDPOINT_ROLE role on $VAPP_PATH"

compute_resource=""
if [ -n "$CLUSTER_PATH" ]; then
  compute_resource=$CLUSTER_PATH
else
  compute_resource=$RP_PATH
fi

echo "Finished"
echo ""
echo "Install command:"
echo ""
echo "vic-machine-linux create --target \"$GOVC_URL\" \ "
echo "  --ops-user \"$OPS_USER\" --ops-password \"$OPS_PASSWORD\" \ "
echo "  --compute-resource $compute_resource \ "
echo "  --bridge-network \"$BRIDGE_NETWORK\" \ "
if [ -n "$CONTAINER_NETWORK_PATH" ]; then
  echo "  --container-network \"$CONTAINER_NETWORK\" \ "
fi
