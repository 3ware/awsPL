# Trouble Shooting AWS Private Link

Being from a networking background, I like to see packets to troubleshoot stuff. I'm currently working with 
AWS Private Links and one of our connections has connectivity problems. So, I decided to spin up a lab using terraform
to see how I can use network flow logs to troubleshoot their problem.

# Problem Solved

I followed the AWS network flow logs guide to export the VPC logs to CloudWatch. At first all I could see was a lot of messages without any IPs/Ports/Flags with a status of NO DATA. BUT, I could see something, so we're off to good start.

I tweaked the aggregation level to 1 minute. After a couple more connection attempts from my EC2 to my Interface endpoint I could see some packets with something useful, like a SRC_IP and a DST_IP, in them. I filtered on the DST_IP - the IP assigned dynamically to the interface endpoint in the subnet - and low and behold I could see the traffic was being REJECTED by the security group applied to the EC2 ENI (NIC to you and me)

A quick update to permit outbound traffic on the securtiy group (I thought outbound traffic was permitted by default) and BOOM, 3-way-handshake complete, AND I can see the packets on every ENI in the path - Pretty good.

And, thanks to the beauty of terraform, I can tear the whole thing down before Amazon charges me for anything.
