#!/bin/sh

MF_KEYPAIR_NAME=blockchain
MF_AMI_ID=ami-011b3ccf1bd6db744
MF_INSTANCE_TYPE=t2.micro
MF_PUBLIC_IP1=52.86.146.171
MF_IAM_ROLE=MQFELLOW-S3FullAccess
MF_USER_DATA_LOCATION=file:///Users/hoffman/workspaces/mq-stuff/userdata.txt

#create vpc
MF_VPCID=`aws ec2 create-vpc --cidr-block 172.17.0.0/16 | jq --raw-output '.Vpc.VpcId'`
echo $MF_VPCID

#create public subnet
MF_SUBNET_ID=`aws ec2 create-subnet --vpc-id $MF_VPCID --cidr-block 172.17.1.0/24 --availability-zone us-east-1a | jq --raw-output '.Subnet.SubnetId'`
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
