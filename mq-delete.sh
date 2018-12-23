
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
