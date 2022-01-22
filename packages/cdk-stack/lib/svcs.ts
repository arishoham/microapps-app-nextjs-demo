import { CfnOutput, RemovalPolicy, Stack, StackProps } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import SharedProps from './SharedProps';
import { MicroAppsAppNextjsDemo } from '@pwrdrvr/microapps-app-nextjs-demo-cdk';
import { Env } from './Types';

export interface ISvcsProps extends StackProps {
  local: {
    appName: string;
  };
  shared: SharedProps;
}

export class SvcsStack extends Stack {
  constructor(scope: Construct, id: string, props: ISvcsProps) {
    super(scope, id, props);

    const { appName } = props.local;
    const { shared } = props;

    // TODO: Allow sharp layer to be omitted
    const sharpLayer = lambda.LayerVersion.fromLayerVersionArn(
      this,
      'sharp-lambda-layer',
      `arn:aws:lambda:${shared.region}:${shared.account}:layer:sharp-heic:1`,
    );

    const app = new MicroAppsAppNextjsDemo(this, 'app', {
      functionName: `microapps-app-${appName}${shared.envSuffix}${shared.prSuffix}`,
      staticAssetsS3Bucket: s3.Bucket.fromBucketName(this, 'apps-bucket', shared.s3BucketName),
      nodeEnv: shared.env as Env,
      removalPolicy: shared.isPR ? RemovalPolicy.DESTROY : RemovalPolicy.RETAIN,
      sharpLayer,
    });

    // Export the latest version published
    new CfnOutput(this, 'app-latest-version', {
      value: app.lambdaFunction.latestVersion.version,
      exportName: `microapps-app-version-${appName}${shared.envSuffix}${shared.prSuffix}`,
    });
  }
}
