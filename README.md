# quickstart-sap-data-hub-eks
## SAP Data Hub on Amazon EKS


This Quick Start automatically deploys an SAP Data Hub on Amazon EKS environment on the AWS Cloud.

SAP Data Hub provides a set of technologies for data orchestration, metadata management, data governance and integration of your  SAP data with AWS services (such as Amazon S3). 

SAP products and applications such as SAP Business Suite, S/4HANA, SAP Business Warehouse (SAP BW), and SAP BW/4HANA, SAP SuccessFactors, SAP Cloud Platform can be connected with SAP Data Hub. 

AWS services like Amazon S3 can also be integrated with SAP Data Hub on Amazon EKS.

The Quick Start offers two deployment options:

- Deploying SAP Data Hub into a new virtual private cloud (VPC) that's configured for security, scalability, and high availability 
- Deploying SAP Data Hub into an existing VPC in your AWS account

You can also use the AWS CloudFormation templates as a starting point for your own implementation.

![Quick Start architecture for SAP DataHub on Amazon EKS](https://github.com/aws-quickstart/quickstart-sap-datahub-eks/blob/develop/assets/sap_data_hub_architecture.png)

The deployment and configuration tasks are automated by AWS CloudFormation templates that you can customize during launch. 

To clone this repo, use the following steps:

1) from your git client, type:

	git clone  git@github.com:aws-quickstart/quickstart-sap-datahub-eks.git

   This will create a directory called quickstart-sap-datahub-eks for you.

2) while still using your git client, cd into the quickstart-sap-datahub-eks directory

3) from the quickstart-sap-datahub-eks, type this command to update all the linked git submodules:

	git submuodules update --init --remote --recursive

4) now that all of the files have been cloned, you can modify them to meet your requirements or upload them as is into your Amazon S3 bucket:

	aws sync sync quickstart-sap-datahub-eks s3://my-S3-bucket-name/quickstart-sap-datahub-eks/

   Now that the files are in Amazon S3, you can run the Quick Start from your CloudFormation console.

For architectural details, step-by-step instructions, and customization options please contact us.

To post feedback, submit feature ideas, or report bugs, use the **Issues** section of this GitHub repo.

If you'd like to submit code for this Quick Start, please review the [AWS Quick Start Contributor's Kit](https://aws-quickstart.github.io/).


