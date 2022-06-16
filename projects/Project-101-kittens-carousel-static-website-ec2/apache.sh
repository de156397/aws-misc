#!/bin/bash
yum -y update
yum -y install httpd
chmod a+r /var/www/html
cd /var/www/html
wget https://raw.githubusercontent.com/de156397/aws-misc/main/projects/Project-101-kittens-carousel-static-website-ec2/static-web/{index.html,cat{0..2}.jpg,cat3.png}
systemctl enable httpd
systemctl start httpd