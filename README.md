# auto-mq-install-vpc-public-subnet
Install MQ in VPC with public subnet - auto

```

==========

Automate

use jq to capture values. https://jqplay.org/
example describe route - .RouteTables | .[] | .VpcId
jq --raw-output '.Vpc.VpcId'

#!/bin/sh

#MF_KEYPAIR_NAME=blockchain
MF_KEYPAIR_NAME=mqfellow-us-west-2
#MF_AMI_ID=ami-011b3ccf1bd6db744
MF_AMI_ID=ami-036affea69a1101c9
MF_INSTANCE_TYPE=t2.large
#MF_PUBLIC_IP1=52.86.146.171
MF_PUBLIC_IP1=52.42.174.228
MF_IAM_ROLE=MQFELLOW-S3FullAccess
MF_USER_DATA_LOCATION=file:///Users/hoffman/workspaces/mq-stuff/userdata.txt
#MF_AVAILABILITY_ZONE=us-east-1a
MF_AVAILABILITY_ZONE=us-west-2a

#create vpc
MF_VPCID=`aws ec2 create-vpc --cidr-block 172.17.0.0/16 | jq --raw-output '.Vpc.VpcId'`
echo $MF_VPCID

#create public subnet
MF_SUBNET_ID=`aws ec2 create-subnet --vpc-id $MF_VPCID --cidr-block 172.17.1.0/24 --availability-zone $MF_AVAILABILITY_ZONE | jq --raw-output '.Subnet.SubnetId'`
echo $MF_SUBNET_ID

#create igw
MF_IGW_ID=`aws ec2 create-internet-gateway | jq --raw-output '.InternetGateway.InternetGatewayId'`
echo $MF_IGW_ID

#attach igw
aws ec2 attach-internet-gateway --vpc-id $MF_VPCID --internet-gateway-id $MF_IGW_ID

#create route-table
MF_RT_TBL_ID=`aws ec2 create-route-table --vpc-id $MF_VPCID | jq --raw-output '.RouteTable.RouteTableId'`
echo $MF_RT_TBL_ID

#create route
aws ec2 create-route --route-table-id $MF_RT_TBL_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $MF_IGW_ID

#describe route table 
aws ec2 describe-route-tables --route-table-id $MF_RT_TBL_ID

#describe subnet
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$MF_VPCID" --query 'Subnets[*].{ID:SubnetId,CIDR:CidrBlock}'

#associate subnet to route table
aws ec2 associate-route-table  --subnet-id $MF_SUBNET_ID --route-table-id $MF_RT_TBL_ID

#describe route table 
aws ec2 describe-route-tables --route-table-id $MF_RT_TBL_ID

#optional keypair generation. use existing one
#aws ec2 delete-key-pair --key-name $MF_KEYPAIR_NAME
#rm -f $MF_KEYPAIR_NAME.pem
#aws ec2 create-key-pair --key-name $MF_KEYPAIR_NAME --query 'KeyMaterial' --output text > $MF_KEYPAIR_NAME.pem
#chmod 400 $MF_KEYPAIR_NAME.pem

MF_SG_GRPID1=`aws ec2 create-security-group --group-name SSHAccess --description "Security group for SSH access" --vpc-id $MF_VPCID | jq --raw-output '.GroupId'`
echo $MF_SG_GRPID1

aws ec2 authorize-security-group-ingress --group-id $MF_SG_GRPID1 --protocol tcp --port 22 --cidr 0.0.0.0/0

MF_SG_GRPID2=`aws ec2 create-security-group --group-name MQListener --description "Security group for MQListener access" --vpc-id $MF_VPCID | jq --raw-output '.GroupId'`
echo $MF_SG_GRPID2

aws ec2 authorize-security-group-ingress --group-id $MF_SG_GRPID2 --protocol tcp --port 1414 --cidr 0.0.0.0/0

MF_INSTANCE_IP1=`aws ec2 run-instances --image-id $MF_AMI_ID --count 1 --instance-type $MF_INSTANCE_TYPE --key-name $MF_KEYPAIR_NAME --security-group-ids $MF_SG_GRPID1 $MF_SG_GRPID2 --subnet-id $MF_SUBNET_ID --iam-instance-profile Name=$MF_IAM_ROLE --user-data $MF_USER_DATA_LOCATION | jq --raw-output '.Instances | .[0].InstanceId'`
echo $MF_INSTANCE_IP1

#optional - create elastic ip to attach to EC2 - aws ec2 allocate-address

# wait for the ec2 to start
# sleep 40

state=`aws ec2 describe-instances --instance-ids $MF_INSTANCE_IP1 --query 'Reservations[].Instances[0].[State.Name]' --output text
`
while [ "$state" != "running" ]
do
    sleep 5
    state=`aws ec2 describe-instances --instance-ids $MF_INSTANCE_IP1 --query 'Reservations[].Instances[0].[State.Name]' --output text`
    echo $state
done

#attach public IP to EC2
aws ec2 associate-address --instance-id $MF_INSTANCE_IP1 --public-ip $MF_PUBLIC_IP1

JSON_STRING=$( jq -n \
                  --arg vpcId "$MF_VPCID" \
                  --arg subnetId "$MF_SUBNET_ID" \
                  --arg internetGatewayId "$MF_IGW_ID" \
                  --arg routeTableId "$MF_RT_TBL_ID" \
                  --arg instanceId "$MF_INSTANCE_IP1" \
                  --arg securityGroupId1 "$MF_SG_GRPID1" \
                  --arg securityGroupId2 "$MF_SG_GRPID2" \
                  '{vpcId: $vpcId, subnetId: $subnetId, internetGatewayId: $internetGatewayId, routeTableId: $routeTableId, instanceId: $instanceId, securityGroupId1: $securityGroupId1, securityGroupId2: $securityGroupId2 }' )

echo $JSON_STRING > mq-delete-input.json


#!/bin/sh

MF_INSTANCE_IP1=`cat mq-delete-input.json | jq --raw-output '.instanceId'`
echo $MF_INSTANCE_IP1

MF_SG_GRPID1=`cat mq-delete-input.json | jq --raw-output '.securityGroupId1'`
echo $MF_SG_GRPID1

MF_SG_GRPID2=`cat mq-delete-input.json | jq --raw-output '.securityGroupId2'`
echo $MF_SG_GRPID2

MF_SUBNET_ID=`cat mq-delete-input.json | jq --raw-output '.subnetId'`
echo $MF_SUBNET_ID

MF_RT_TBL_ID=`cat mq-delete-input.json | jq --raw-output '.routeTableId'`
echo $MF_RT_TBL_ID

MF_IGW_ID=`cat mq-delete-input.json | jq --raw-output '.internetGatewayId'`
echo $MF_IGW_ID

MF_VPCID=`cat mq-delete-input.json | jq --raw-output '.vpcId'`
echo $MF_VPCID

aws ec2 terminate-instances --instance-ids $MF_INSTANCE_IP1
state=`aws ec2 describe-instances --instance-ids $MF_INSTANCE_IP1 --query 'Reservations[].Instances[0].[State.Name]' --output text
`
echo $state
while [ "$state" != "terminated" ]
do
    sleep 10
    state=`aws ec2 describe-instances --instance-ids $MF_INSTANCE_IP1 --query 'Reservations[].Instances[0].[State.Name]' --output text`
    echo $state
done
aws ec2 delete-security-group --group-id $MF_SG_GRPID1
aws ec2 delete-security-group --group-id $MF_SG_GRPID2
aws ec2 delete-subnet --subnet-id $MF_SUBNET_ID
aws ec2 delete-route-table --route-table-id $MF_RT_TBL_ID
aws ec2 detach-internet-gateway --internet-gateway-id $MF_IGW_ID --vpc-id $MF_VPCID
aws ec2 delete-internet-gateway --internet-gateway-id $MF_IGW_ID
aws ec2 delete-vpc --vpc-id $MF_VPCID

i-0dbe42ffe158d581a

aws ec2 terminate-instances --instance-ids i-0dbe42ffe158d581a

aws ec2 describe-instances --instance-ids i-09c3816dba01ec8db --query 'Reservations[].Instances[0].[State.Name]' --output text

=====================



aws ec2 terminate-instances --instance-ids i-0142a88327f271107

state=`aws ec2 describe-instances --instance-ids i-0142a88327f271107 --query 'Reservations[].Instances[0].[State.Name]' --output text
`
while [ "$state" == "running" ]
do
    sleep 5
    state=`aws ec2 describe-instances --instance-ids i-0142a88327f271107 --query 'Reservations[].Instances[0].[State.Name]' --output text`
    echo $state
done

vpc-014b2862e6fe061cb
subnet-08aaf4f9904806ef4
igw-0ebaeb70b0820fd56

aws ec2 delete-security-group --group-id sg-0f54a4684a4133575
aws ec2 delete-security-group --group-id sg-0fce912bb46b485d4
aws ec2 delete-subnet --subnet-id subnet-08aaf4f9904806ef4
aws ec2 delete-route-table --route-table-id rtb-081675696ad898f5d
aws ec2 detach-internet-gateway --internet-gateway-id igw-0ebaeb70b0820fd56 --vpc-id vpc-014b2862e6fe061cb
aws ec2 delete-internet-gateway --internet-gateway-id igw-0ebaeb70b0820fd56
aws ec2 delete-vpc --vpc-id vpc-014b2862e6fe061cb


#connect to EC2

ssh -i "$MF_KEYPAIR_NAME.pem" ec2-user@$MF_PUBLIC_IP1

# then create private subnet for client-app testing.

aws ec2 associate-address --instance-id i-0eb3daaa43ba02eda --public-ip 52.86.146.171




===========
Delete VPC

aws ec2 delete-vpc --vpc-id vpc-02b6f89f7f60fa84a

ec2 and eni to delete

MF_DEL_INSTANCEID=`aws ec2 describe-instances --filters Name=vpc-id,Values=vpc-02b6f89f7f60fa84a --query 'Reservations[].Instances[0].[InstanceId]' --output text`
echo $MF_DEL_INSTANCEID

aws ec2 terminate-instances --instance-ids $MF_DEL_INSTANCEID
aws ec2 describe-instances --instance-ids $MF_DEL_INSTANCEID

aws ec2 delete-vpc --vpc-id vpc-02b6f89f7f60fa84a

Are you sure that you want to delete this VPC (vpc-02b6f89f7f60fa84a)?

Deleting this VPC will also delete these objects associated with this VPC in this region:

Subnets
Security Groups
Network ACLs
Internet Gateways
Egress Only Internet Gateways
Route Tables
Network Interfaces
Peering Connections
Endpoints

https://serverfault.com/questions/578921/how-would-you-go-about-listing-instances-using-aws-cli-in-certain-vpc-with-the-t

aws ec2 describe-instances --filters Name=vpc-id,Values=vpc-02b6f89f7f60fa84a --query 'Reservations[].Instances[].[PrivateIpAddress,InstanceId,Tags[?Key==`Name`].Value[]]' --output text




--------

Manually, create vpc with public subnet and using nat gw for outbound access and eip for inbound access
use the wizard to create vpc with private and public subnet

# create a vpc

$ aws ec2 create-vpc --cidr-block 172.17.0.0/16
{
    "Vpc": {
        "VpcId": "vpc-02b6f89f7f60fa84a", 
        "InstanceTenancy": "default", 
        "Tags": [], 
        "CidrBlockAssociationSet": [
            {
                "AssociationId": "vpc-cidr-assoc-0247751aef32aa8e6", 
                "CidrBlock": "172.17.0.0/16", 
                "CidrBlockState": {
                    "State": "associated"
                }
            }
        ], 
        "Ipv6CidrBlockAssociationSet": [], 
        "State": "pending", 
        "DhcpOptionsId": "dopt-9763c0f3", 
        "CidrBlock": "172.17.0.0/16", 
        "IsDefault": false
    }
}

# create a public subnet

$ aws ec2 create-subnet --vpc-id vpc-02b6f89f7f60fa84a --cidr-block 172.17.1.0/24 --availability-zone us-east-1a
{
    "Subnet": {
        "AvailabilityZone": "us-east-1a", 
        "AvailableIpAddressCount": 251, 
        "DefaultForAz": false, 
        "Ipv6CidrBlockAssociationSet": [], 
        "VpcId": "vpc-02b6f89f7f60fa84a", 
        "State": "pending", 
        "MapPublicIpOnLaunch": false, 
        "SubnetId": "subnet-0dfd4298b42238a64", 
        "CidrBlock": "172.17.1.0/24", 
        "AssignIpv6AddressOnCreation": false
    }
}

$ aws ec2 create-internet-gateway
{
    "InternetGateway": {
        "Tags": [], 
        "Attachments": [], 
        "InternetGatewayId": "igw-0bead20e948ff7985"
    }
}

$ aws ec2 attach-internet-gateway --vpc-id vpc-02b6f89f7f60fa84a --internet-gateway-id igw-0bead20e948ff7985

$ aws ec2 create-route-table --vpc-id vpc-02b6f89f7f60fa84a
{
    "RouteTable": {
        "Associations": [], 
        "RouteTableId": "rtb-0fd76e77c43cab09a", 
        "VpcId": "vpc-02b6f89f7f60fa84a", 
        "PropagatingVgws": [], 
        "Tags": [], 
        "Routes": [
            {
                "GatewayId": "local", 
                "DestinationCidrBlock": "172.17.0.0/16", 
                "State": "active", 
                "Origin": "CreateRouteTable"
            }
        ]
    }
}

--

$ aws ec2 create-route --route-table-id rtb-0fd76e77c43cab09a --destination-cidr-block 0.0.0.0/0 --gateway-id igw-0bead20e948ff7985
{
    "Return": true
}

$ aws ec2 describe-route-tables --route-table-id rtb-0fd76e77c43cab09a

{
    "RouteTables": [
        {
            "Associations": [], 
            "RouteTableId": "rtb-0fd76e77c43cab09a", 
            "VpcId": "vpc-02b6f89f7f60fa84a", 
            "PropagatingVgws": [], 
            "Tags": [], 
            "Routes": [
                {
                    "GatewayId": "local", 
                    "DestinationCidrBlock": "172.17.0.0/16", 
                    "State": "active", 
                    "Origin": "CreateRouteTable"
                }, 
                {
                    "GatewayId": "igw-0bead20e948ff7985", 
                    "DestinationCidrBlock": "0.0.0.0/0", 
                    "State": "active", 
                    "Origin": "CreateRoute"
                }
            ]
        }
    ]
}

$ aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-02b6f89f7f60fa84a" --query 'Subnets[*].{ID:SubnetId,CIDR:CidrBlock}'

[
    {
        "CIDR": "172.17.1.0/24", 
        "ID": "subnet-0dfd4298b42238a64"
    }
]

# https://docs.aws.amazon.com/vpc/latest/userguide/vpc-subnets-commands-example.html

$ aws ec2 associate-route-table  --subnet-id subnet-0dfd4298b42238a64 --route-table-id rtb-0fd76e77c43cab09a
{
    "AssociationId": "rtbassoc-0b83d8391624ee447"
}


$ aws ec2 describe-route-tables --route-table-id rtb-0fd76e77c43cab09a
{
    "RouteTables": [
        {
            "Associations": [
                {
                    "SubnetId": "subnet-0dfd4298b42238a64", 
                    "RouteTableAssociationId": "rtbassoc-0b83d8391624ee447", 
                    "Main": false, 
                    "RouteTableId": "rtb-0fd76e77c43cab09a"
                }
            ], 
            "RouteTableId": "rtb-0fd76e77c43cab09a", 
            "VpcId": "vpc-02b6f89f7f60fa84a", 
            "PropagatingVgws": [], 
            "Tags": [], 
            "Routes": [
                {
                    "GatewayId": "local", 
                    "DestinationCidrBlock": "172.17.0.0/16", 
                    "State": "active", 
                    "Origin": "CreateRouteTable"
                }, 
                {
                    "GatewayId": "igw-0bead20e948ff7985", 
                    "DestinationCidrBlock": "0.0.0.0/0", 
                    "State": "active", 
                    "Origin": "CreateRoute"
                }
            ]
        }
    ]
}

https://docs.aws.amazon.com/vpc/latest/userguide/vpc-subnets-commands-example.html

aws ec2 delete-key-pair --key-name mqfellow
aws ec2 create-key-pair --key-name mqfellow --query 'KeyMaterial' --output text > mqfellow.pem
chmod 400 mqfellow.pem

aws ec2 create-security-group --group-name SSHAccess --description "Security group for SSH access" --vpc-id vpc-02b6f89f7f60fa84a
{
    "GroupId": "sg-073d87dd5c7432f1b"
}
aws ec2 authorize-security-group-ingress --group-id sg-073d87dd5c7432f1b --protocol tcp --port 22 --cidr 0.0.0.0/0

aws ec2 create-security-group --group-name MQListener --description "Security group for MQListener access" --vpc-id vpc-02b6f89f7f60fa84a
{
    "GroupId": "sg-0068503eacdef98f6"
}
aws ec2 authorize-security-group-ingress --group-id sg-0068503eacdef98f6 --protocol tcp --port 1414 --cidr 0.0.0.0/0

aws ec2 run-instances --image-id ami-011b3ccf1bd6db744 --count 1 --instance-type t2.micro --key-name mqfellow --security-group-ids sg-073d87dd5c7432f1b sg-0068503eacdef98f6 --subnet-id subnet-0dfd4298b42238a64
{
    "Instances": [
        {
            "Monitoring": {
                "State": "disabled"
            }, 
            "PublicDnsName": "", 
            "StateReason": {
                "Message": "pending", 
                "Code": "pending"
            }, 
            "State": {
                "Code": 0, 
                "Name": "pending"
            }, 
            "EbsOptimized": false, 
            "LaunchTime": "2018-12-22T22:41:03.000Z", 
            "PrivateIpAddress": "172.17.1.82", 
            "ProductCodes": [], 
            "VpcId": "vpc-02b6f89f7f60fa84a", 
            "StateTransitionReason": "", 
            "InstanceId": "i-09d45425179a44d23", 
            "ImageId": "ami-011b3ccf1bd6db744", 
            "PrivateDnsName": "ip-172-17-1-82.ec2.internal", 
            "KeyName": "mqfellow", 
            "SecurityGroups": [
                {
                    "GroupName": "MQListener", 
                    "GroupId": "sg-0068503eacdef98f6"
                }, 
                {
                    "GroupName": "SSHAccess", 
                    "GroupId": "sg-073d87dd5c7432f1b"
                }
            ], 
            "ClientToken": "", 
            "SubnetId": "subnet-0dfd4298b42238a64", 
            "InstanceType": "t2.micro", 
            "NetworkInterfaces": [
                {
                    "Status": "in-use", 
                    "MacAddress": "0e:2e:44:0e:59:c6", 
                    "SourceDestCheck": true, 
                    "VpcId": "vpc-02b6f89f7f60fa84a", 
                    "Description": "", 
                    "NetworkInterfaceId": "eni-09e6482f92c956b8d", 
                    "PrivateIpAddresses": [
                        {
                            "Primary": true, 
                            "PrivateIpAddress": "172.17.1.82"
                        }
                    ], 
                    "SubnetId": "subnet-0dfd4298b42238a64", 
                    "Attachment": {
                        "Status": "attaching", 
                        "DeviceIndex": 0, 
                        "DeleteOnTermination": true, 
                        "AttachmentId": "eni-attach-0a06d733f67363884", 
                        "AttachTime": "2018-12-22T22:41:03.000Z"
                    }, 
                    "Groups": [
                        {
                            "GroupName": "MQListener", 
                            "GroupId": "sg-0068503eacdef98f6"
                        }, 
                        {
                            "GroupName": "SSHAccess", 
                            "GroupId": "sg-073d87dd5c7432f1b"
                        }
                    ], 
                    "Ipv6Addresses": [], 
                    "OwnerId": "962934755172", 
                    "PrivateIpAddress": "172.17.1.82"
                }
            ], 
            "SourceDestCheck": true, 
            "Placement": {
                "Tenancy": "default", 
                "GroupName": "", 
                "AvailabilityZone": "us-east-1a"
            }, 
            "Hypervisor": "xen", 
            "BlockDeviceMappings": [], 
            "Architecture": "x86_64", 
            "RootDeviceType": "ebs", 
            "RootDeviceName": "/dev/sda1", 
            "VirtualizationType": "hvm", 
            "AmiLaunchIndex": 0
        }
    ], 
    "ReservationId": "r-00ca42856c5a6d4de", 
    "Groups": [], 
    "OwnerId": "962934755172"
}

$ aws ec2 allocate-address
{
    "PublicIp": "52.86.146.171", 
    "Domain": "vpc", 
    "AllocationId": "eipalloc-0bb5381b69f250d2e"
}

$ aws ec2 associate-address --instance-id i-09d45425179a44d23 --public-ip 52.86.146.171
{
    "AssociationId": "eipassoc-0e982318f8aaac5cf"
}

ssh -i "mqfellow.pem" ec2-user@52.86.146.171

# then create private subnet for client-app testing.


========


# create elastic ip for use in nat-gw

$ aws ec2 allocate-address
{
    "PublicIp": "35.172.42.55", 
    "Domain": "vpc", 
    "AllocationId": "eipalloc-0f8e95babe2cd190f"
}

$ aws ec2 create-nat-gateway --subnet-id subnet-082116a405c173647 --allocation-id eipalloc-0f8e95babe2cd190f
{
    "NatGateway": {
        "NatGatewayAddresses": [
            {
                "AllocationId": "eipalloc-0f8e95babe2cd190f"
            }
        ], 
        "VpcId": "vpc-09d049c8554d486f9", 
        "State": "pending", 
        "NatGatewayId": "nat-050545d514b65d857", 
        "SubnetId": "subnet-082116a405c173647", 
        "CreateTime": "2018-12-22T20:51:48.000Z"
    }
}

$ aws ec2 describe-nat-gateways --nat-gateway-ids nat-050545d514b65d857
{
    "NatGateways": [
        {
            "NatGatewayAddresses": [
                {
                    "PublicIp": "35.172.42.55", 
                    "NetworkInterfaceId": "eni-0d81a8ce68892297c", 
                    "AllocationId": "eipalloc-0f8e95babe2cd190f", 
                    "PrivateIp": "172.17.1.147"
                }
            ], 
            "VpcId": "vpc-09d049c8554d486f9", 
            "Tags": [], 
            "State": "available", 
            "NatGatewayId": "nat-050545d514b65d857", 
            "SubnetId": "subnet-082116a405c173647", 
            "CreateTime": "2018-12-22T21:04:54.000Z"
        }
    ]
}

$ aws ec2 create-route --route-table-id rtb-0d07180bd77cfa1ab --destination-cidr-block 0.0.0.0/0 --nat-gateway-id nat-050545d514b65d857
{
    "Return": true
}

$  aws ec2 describe-route-tables --route-table-id rtb-0d07180bd77cfa1ab
{
    "RouteTables": [
        {
            "Associations": [], 
            "RouteTableId": "rtb-0d07180bd77cfa1ab", 
            "VpcId": "vpc-09d049c8554d486f9", 
            "PropagatingVgws": [], 
            "Tags": [], 
            "Routes": [
                {
                    "GatewayId": "local", 
                    "DestinationCidrBlock": "172.17.0.0/16", 
                    "State": "active", 
                    "Origin": "CreateRouteTable"
                }, 
                {
                    "Origin": "CreateRoute", 
                    "DestinationCidrBlock": "0.0.0.0/0", 
                    "NatGatewayId": "nat-050545d514b65d857", 
                    "State": "active"
                }
            ]
        }
    ]
}


# attach nat-gw for outbound access

$ aws ec2 attach-internet-gateway --vpc-id vpc-0596bf3f887241388 --internet-gateway-id igw-0f74aa21addb03abf


create elastic ip




create nat-gw
https://docs.aws.amazon.com/cli/latest/reference/ec2/create-nat-gateway.html
To create a NAT gateway
aws ec2 create-nat-gateway --subnet-id subnet-1a2b3c4d --allocation-id eipalloc-37fc1a52


create route for nat-gw
https://docs.aws.amazon.com/cli/latest/reference/ec2/create-route.html



======================



# vpc https://docs.aws.amazon.com/cli/latest/reference/ec2/create-vpc.html

http://www.subnet-calculator.com/cidr.php

CIDR 172.17.0.1/16
Range 172.17.0.1 - 172.17.255.254
IPs 65534



$ aws ec2 create-vpc --cidr-block 172.17.0.1/16
{
    "Vpc": {
        "VpcId": "vpc-0596bf3f887241388", 
        "InstanceTenancy": "default", 
        "Tags": [], 
        "CidrBlockAssociationSet": [
            {
                "AssociationId": "vpc-cidr-assoc-0030243bd0956c4eb", 
                "CidrBlock": "172.17.0.0/16", 
                "CidrBlockState": {
                    "State": "associated"
                }
            }
        ], 
        "Ipv6CidrBlockAssociationSet": [], 
        "State": "pending", 
        "DhcpOptionsId": "dopt-9763c0f3", 
        "CidrBlock": "172.17.0.0/16", 
        "IsDefault": false
    }
}

# subnet https://docs.aws.amazon.com/cli/latest/reference/ec2/create-subnet.html

https://docs.aws.amazon.com/vpc/latest/userguide/vpc-subnets-commands-example.html

$ aws ec2 create-subnet --vpc-id vpc-0596bf3f887241388 --cidr-block 172.17.1.0/24 --availability-zone us-east-1a
{
    "Subnet": {
        "AvailabilityZone": "us-east-1a", 
        "AvailableIpAddressCount": 251, 
        "DefaultForAz": false, 
        "Ipv6CidrBlockAssociationSet": [], 
        "VpcId": "vpc-0596bf3f887241388", 
        "State": "pending", 
        "MapPublicIpOnLaunch": false, 
        "SubnetId": "subnet-0be687474b26db715", 
        "CidrBlock": "172.17.1.0/24", 
        "AssignIpv6AddressOnCreation": false
    }
}

$ aws ec2 create-subnet --vpc-id vpc-0596bf3f887241388 --cidr-block 172.17.2.0/24 --availability-zone us-east-1b
{
    "Subnet": {
        "AvailabilityZone": "us-east-1b", 
        "AvailableIpAddressCount": 251, 
        "DefaultForAz": false, 
        "Ipv6CidrBlockAssociationSet": [], 
        "VpcId": "vpc-0596bf3f887241388", 
        "State": "pending", 
        "MapPublicIpOnLaunch": false, 
        "SubnetId": "subnet-0eef69219f081eeb4", 
        "CidrBlock": "172.17.2.0/24", 
        "AssignIpv6AddressOnCreation": false
    }
}


$ aws ec2 create-subnet --vpc-id vpc-0596bf3f887241388 --cidr-block 172.17.3.0/24 --availability-zone us-east-1c
{
    "Subnet": {
        "AvailabilityZone": "us-east-1c", 
        "AvailableIpAddressCount": 251, 
        "DefaultForAz": false, 
        "Ipv6CidrBlockAssociationSet": [], 
        "VpcId": "vpc-0596bf3f887241388", 
        "State": "pending", 
        "MapPublicIpOnLaunch": false, 
        "SubnetId": "subnet-069b809b1241f7f01", 
        "CidrBlock": "172.17.3.0/24", 
        "AssignIpv6AddressOnCreation": false
    }
}

$ aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-0596bf3f887241388" --query 'Subnets[*].{ID:SubnetId,CIDR:CidrBlock}'
[
    {
        "CIDR": "172.17.3.0/24", 
        "ID": "subnet-069b809b1241f7f01"
    }, 
    {
        "CIDR": "172.17.2.0/24", 
        "ID": "subnet-0eef69219f081eeb4"
    }, 
    {
        "CIDR": "172.17.1.0/24", 
        "ID": "subnet-0be687474b26db715"
    }
]

# add internet gateway to the vpc - will use eni instead of subnet/public ip

https://docs.aws.amazon.com/vpc/latest/userguide/vpc-subnets-commands-example.html

$ aws ec2 create-internet-gateway
{
    "InternetGateway": {
        "Tags": [], 
        "Attachments": [], 
        "InternetGatewayId": "igw-0f74aa21addb03abf"
    }
}

$ aws ec2 attach-internet-gateway --vpc-id vpc-0596bf3f887241388 --internet-gateway-id igw-0f74aa21addb03abf

$ aws ec2 create-route-table --vpc-id vpc-0596bf3f887241388
{
    "RouteTable": {
        "Associations": [], 
        "RouteTableId": "rtb-08a70915aeae64e40", 
        "VpcId": "vpc-0596bf3f887241388", 
        "PropagatingVgws": [], 
        "Tags": [], 
        "Routes": [
            {
                "GatewayId": "local", 
                "DestinationCidrBlock": "172.17.0.0/16", 
                "State": "active", 
                "Origin": "CreateRouteTable"
            }
        ]
    }
}

$ aws ec2 create-route --route-table-id rtb-08a70915aeae64e40 --destination-cidr-block 0.0.0.0/0 --gateway-id igw-0f74aa21addb03abf
{
    "Return": true
}

$ aws ec2 describe-route-tables --route-table-id rtb-08a70915aeae64e40

{
    "RouteTables": [
        {
            "Associations": [], 
            "RouteTableId": "rtb-08a70915aeae64e40", 
            "VpcId": "vpc-0596bf3f887241388", 
            "PropagatingVgws": [], 
            "Tags": [], 
            "Routes": [
                {
                    "GatewayId": "local", 
                    "DestinationCidrBlock": "172.17.0.0/16", 
                    "State": "active", 
                    "Origin": "CreateRouteTable"
                }, 
                {
                    "GatewayId": "igw-0f74aa21addb03abf", 
                    "DestinationCidrBlock": "0.0.0.0/0", 
                    "State": "active", 
                    "Origin": "CreateRoute"
                }
            ]
        }
    ]
}

$ aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-0596bf3f887241388" --query 'Subnets[*].{ID:SubnetId,CIDR:CidrBlock}'

[
    {
        "CIDR": "172.17.3.0/24", 
        "ID": "subnet-069b809b1241f7f01"
    }, 
    {
        "CIDR": "172.17.2.0/24", 
        "ID": "subnet-0eef69219f081eeb4"
    }, 
    {
        "CIDR": "172.17.1.0/24", 
        "ID": "subnet-0be687474b26db715"
    }
]

# https://docs.aws.amazon.com/vpc/latest/userguide/vpc-subnets-commands-example.html

$ aws ec2 associate-route-table  --subnet-id subnet-0be687474b26db715 --route-table-id rtb-08a70915aeae64e40
{
    "AssociationId": "rtbassoc-0769188220e8ca266"
}


$ aws ec2 associate-route-table  --subnet-id subnet-0eef69219f081eeb4 --route-table-id rtb-08a70915aeae64e40
{
    "AssociationId": "rtbassoc-0537ed30f1f0e4780"
}

$ aws ec2 associate-route-table  --subnet-id subnet-069b809b1241f7f01 --route-table-id rtb-08a70915aeae64e40
{
    "AssociationId": "rtbassoc-01ae1d6bfbbb3ecdc"
}

map-public-ip-on-launch - will not use this. will use eni/public ip

# sg https://docs.aws.amazon.com/vpc/latest/userguide/vpc-subnets-commands-example.html

$ aws ec2 create-security-group --group-name SSHAccess --description "Security group for SSH access" --vpc-id vpc-0596bf3f887241388
{
    "GroupId": "sg-0087274817f44a140"
}

ssh 
aws ec2 authorize-security-group-ingress --group-id sg-0087274817f44a140 --protocol tcp --port 22 --cidr 0.0.0.0/0

mq
aws ec2 authorize-security-group-ingress --group-id sg-0087274817f44a140 --protocol tcp --port 1414 --cidr 0.0.0.0/0

launch
$ aws ec2 run-instances --image-id ami-011b3ccf1bd6db744 --count 1 --instance-type t2.large --key-name blockchain --security-group-ids sg-0087274817f44a140 --subnet-id subnet-0be687474b26db715

aws ec2 modify-subnet-attribute --subnet-id subnet-0be687474b26db715 --map-public-ip-on-launch


Clean Up
aws ec2 delete-security-group --group-id sg-0087274817f44a140
aws ec2 delete-subnet --subnet-id subnet-0be687474b26db715
aws ec2 delete-subnet --subnet-id subnet-0eef69219f081eeb4
aws ec2 delete-subnet --subnet-id subnet-069b809b1241f7f01
aws ec2 delete-route-table --route-table-id rtb-08a70915aeae64e40
aws ec2 detach-internet-gateway --internet-gateway-id igw-0f74aa21addb03abf --vpc-id vpc-0596bf3f887241388
aws ec2 delete-internet-gateway --internet-gateway-id igw-0f74aa21addb03abf
aws ec2 delete-vpc --vpc-id vpc-0596bf3f887241388

Example: Create an IPv4 VPC and Subnets Using the AWS CLI
https://docs.aws.amazon.com/vpc/latest/userguide/vpc-subnets-commands-example.html


=================




# elb https://docs.aws.amazon.com/cli/latest/reference/elb/create-load-balancer.html

aws elb create-load-balancer --load-balancer-name mqfellowa-lbqae --listeners "Protocol=TCP,LoadBalancerPort=1414,InstanceProtocol=TCP,InstancePort=1414" --subnets subnet-60290b38 subnet-f0ef8595 --security-groups sg-5aecb621 sg-0e14bb35fbe76ed0c

# lc https://docs.aws.amazon.com/cli/latest/reference/autoscaling/create-launch-configuration.html

aws autoscaling create-launch-configuration --launch-configuration-name mqfellowa-lcqae --key-name blockchain --image-id ami-011b3ccf1bd6db744 --instance-type t2.large --security-groups sg-5aecb621 sg-0e14bb35fbe76ed0c --iam-instance-profile MQFELLOW-S3FullAccess --user-data file:///Users/hoffman/workspaces/mq-stuff/userdata.txt

# asg https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-register-lbs-with-asg.html#as-lbs-app-create-lc-cli

aws autoscaling create-auto-scaling-group --auto-scaling-group-name mqfellowa-asgqae   \
--launch-configuration-name mqfellowa-lcqae \
--availability-zones "us-east-1a" "us-east-1b" \
--load-balancer-names "mqfellowa-lbqae" \
--max-size 1 --min-size 1 --desired-capacity 1

# sudo su -

# userdata

#!/bin/bash -ex
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
uname -a
cd ~
curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"
yum install unzip -y
unzip awscli-bundle.zip
./awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws
aws s3 cp s3://mqfellow-us-east-1/mq-installer/IBM_MQ_9.1_LINUX_X86-64_TRIAL.tar.gz /root/IBM_MQ_9.1_LINUX_X86-64_TRIAL.tar.gz
tar -xzvf IBM_MQ_9.1_LINUX_X86-64_TRIAL.tar.gz
cd MQServer
echo 1 | sudo ./mqlicense.sh 
rpm -ivh MQSeriesRuntime*.rpm
rpm -ivh MQSeriesJRE*.rpm
rpm -ivh MQSeriesJava*.rpm
rpm -ivh MQSeriesServer*.rpm
rpm -ivh MQSeriesWeb*.rpm
rpm -ivh MQSeriesFTBase*.rpm
rpm -ivh MQSeriesFTAgent*.rpm
rpm -ivh MQSeriesFTService*.rpm
rpm -ivh MQSeriesFTLogger*.rpm
rpm -ivh MQSeriesFTTools*.rpm
rpm -ivh MQSeriesAMQP*.rpm
rpm -ivh MQSeriesAMS*.rpm
rpm -ivh MQSeriesXRService*.rpm
rpm -ivh MQSeriesExplorer*.rpm
rpm -ivh MQSeriesGSKit*.rpm
rpm -ivh MQSeriesClient*.rpm
rpm -ivh MQSeriesMan*.rpm
rpm -ivh MQSeriesMsg*.rpm
rpm -ivh MQSeriesSamples*.rpm
rpm -ivh MQSeriesSDK*.rpm
rpm -ivh MQSeriesSFBridge*.rpm
rpm -ivh MQSeriesBCBridge*.rpm
rpm -qa | grep MQ
/opt/mqm/bin/setmqinst -i -p /opt/mqm
su - mqm -c 'dspmqver'


```
