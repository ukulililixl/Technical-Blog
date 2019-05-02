AWS Lambda with S3

I record my experience to learn the official tutorial: Using AWS Lambda with Amazon S3 ([tutorial](https://docs.aws.amazon.com/lambda/latest/dg/with-s3-example.html)).

The purpose of the tutorial is to use AWS Lambda to resize the object stored in a *source bucket* and store in a *target bucket*.

##### Create the execution role

We first need to create an execution role:

* This role has the execution permission of our lambda function.
* This role guarantees that our lambda function have access to S3 resources.
* This role guarantees that our lambda function can write logs to CloudWatch Logs.

The procedure to create the role:

* Go to the [roles page](https://console.aws.amazon.com/iam/home?#/roles) and click the button with "create role"
  * ![](figs/createrole1.png)
* Choose "Lambda" and click "next"
  * ![](figs/createrole2.png)
* Choose "AWSLambdaExecute" and click "next"
  * ![](figs/createrole3.png)
* Set the name as "lambda-s3-role"
  * ![](figs/createrole4.png)

##### Create S3 bucket

Here we create two buckets in our Amazon S3.

- shellsvirginiabucket
  - Store the original object, which will trigger the execution of lambda function
- shellsvirginiabucketresized
  - Store the resized object.

Please note that buckets in different region with our function will fail to trigger the function execution.

Now we choose to create bucket in **us-east-1(N. Virgina)**.

After we create the buckets, we then upload a sample picture into it (daao.jpg).

##### Create the function

We use the code in **java8**. Here is the sample code in the tutorial. And we use **mvn** to create the package.

- First, we need to prepare the project directory in our local file system.

  ```shell
  $> tree lambda-proj
  lambda-proj/
  ├── pom.xml
  └── src
      └── main
          └── java
              └── example
                  └── S3EventProcessorCreateThumbnail.java
  ```

- pom.xml

  ```xml
  <project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/maven-v4_0_0.xsd">
    <modelVersion>4.0.0</modelVersion> <!-- Special for maven2-->
  
    <!-- The purpose of groupId and artifactId is to make sure that this project can be uniquely identified if you publish the project in maven central repository. Here we only use for our own test purpose. So take it easy.-->
    <groupId>doc-examples</groupId>
    <artifactId>lambda-java-example</artifactId>
     
    <!-- packaging specifies the method to package the project. We choose jar here. -->
    <packaging>jar</packaging>
    
    <!--Current version of the project-->
    <version>1.0-SNAPSHOT</version>
    <name>lambda-java-example</name>
  
    <!--dependencies includes all dependencies that current project needs.-->
    <dependencies>
      <!--Each dependency should include groupId, artifactId and version, such that maven can find it in the repository and download at the first compilation. As specified in the tutorial, we need the following three dependency in the tutorial.-->  
      <dependency>
      <groupId>com.amazonaws</groupId>
      <artifactId>aws-lambda-java-core</artifactId>
      <version>1.1.0</version>
      </dependency>
        
      <dependency>
      <groupId>com.amazonaws</groupId>
      <artifactId>aws-lambda-java-events</artifactId>
      <version>1.3.0</version>
      </dependency>
        
      <dependency>
      <groupId>com.amazonaws</groupId>
      <artifactId>aws-java-sdk-s3</artifactId>
      <version>1.11.0</version>
      </dependency>
        
    </dependencies>
  
    <build>
      <!--Here we list the plugins we need during the build.-->
      <plugins>
        <!--This plugin provides the capability to package the artifact in an uber-jar, including its dependencies and to shade - i.e. rename - the packages of some of the dependencies.-->
        <plugin>
          <groupId>org.apache.maven.plugins</groupId>
          <artifactId>maven-shade-plugin</artifactId>
          <version>2.3</version>
          <configuration>
            <createDependencyReducedPom>false</createDependencyReducedPom>
          </configuration>
          <executions>
            <execution>
              <phase>package</phase>
              <goals>
                <goal>shade</goal>
              </goals>
            </execution>
          </executions>
        </plugin>
      </plugins>
    </build>
  </project>
  ```

* S3EventProcessorCreateThumbnail.java

  ```java
  package example;
  
  import java.awt.Color;
  import java.awt.Graphics2D;
  import java.awt.RenderingHints;
  import java.awt.image.BufferedImage;
  import java.io.ByteArrayInputStream;
  import java.io.ByteArrayOutputStream;
  import java.io.IOException;
  import java.io.InputStream;
  import java.net.URLDecoder;
  import java.util.regex.Matcher;
  import java.util.regex.Pattern;
  
  import javax.imageio.ImageIO;
  
  import com.amazonaws.services.lambda.runtime.Context;
  import com.amazonaws.services.lambda.runtime.RequestHandler;
  import com.amazonaws.services.lambda.runtime.events.S3Event;
  import com.amazonaws.services.s3.AmazonS3;
  import com.amazonaws.services.s3.AmazonS3Client;
  import com.amazonaws.services.s3.event.S3EventNotification.S3EventNotificationRecord;
  import com.amazonaws.services.s3.model.GetObjectRequest;
  import com.amazonaws.services.s3.model.ObjectMetadata;
  import com.amazonaws.services.s3.model.S3Object;
  
  public class S3EventProcessorCreateThumbnail implements
          RequestHandler<S3Event, String> {
      private static final float MAX_WIDTH = 100;
      private static final float MAX_HEIGHT = 100;
      private final String JPG_TYPE = (String) "jpg";
      private final String JPG_MIME = (String) "image/jpeg";
      private final String PNG_TYPE = (String) "png";
      private final String PNG_MIME = (String) "image/png";
  
      public String handleRequest(S3Event s3event, Context context) {
          try {
              S3EventNotificationRecord record = s3event.getRecords().get(0);
  
              String srcBucket = record.getS3().getBucket().getName();
              // Object key may have spaces or unicode non-ASCII characters.
              String srcKey = record.getS3().getObject().getKey()
                      .replace('+', ' ');
              srcKey = URLDecoder.decode(srcKey, "UTF-8");
  
              String dstBucket = srcBucket + "resized";
              String dstKey = "resized-" + srcKey;
  
              // Sanity check: validate that source and destination are different
              // buckets.
              if (srcBucket.equals(dstBucket)) {
                  System.out
                          .println("Destination bucket must not match source bucket.");
                  return "";
              }
  
              // Infer the image type.
              Matcher matcher = Pattern.compile(".*\\.([^\\.]*)").matcher(srcKey);
              if (!matcher.matches()) {
                  System.out.println("Unable to infer image type for key "
                          + srcKey);
                  return "";
              }
              String imageType = matcher.group(1);
              if (!(JPG_TYPE.equals(imageType)) && !(PNG_TYPE.equals(imageType))) {
                  System.out.println("Skipping non-image " + srcKey);
                  return "";
              }
  
              // Download the image from S3 into a stream
              AmazonS3 s3Client = new AmazonS3Client();
              S3Object s3Object = s3Client.getObject(new GetObjectRequest(
                      srcBucket, srcKey));
              InputStream objectData = s3Object.getObjectContent();
  
              // Read the source image
              BufferedImage srcImage = ImageIO.read(objectData);
              int srcHeight = srcImage.getHeight();
              int srcWidth = srcImage.getWidth();
              // Infer the scaling factor to avoid stretching the image
              // unnaturally
              float scalingFactor = Math.min(MAX_WIDTH / srcWidth, MAX_HEIGHT
                      / srcHeight);
              int width = (int) (scalingFactor * srcWidth);
              int height = (int) (scalingFactor * srcHeight);
  
              BufferedImage resizedImage = new BufferedImage(width, height,
                      BufferedImage.TYPE_INT_RGB);
              Graphics2D g = resizedImage.createGraphics();
              // Fill with white before applying semi-transparent (alpha) images
              g.setPaint(Color.white);
              g.fillRect(0, 0, width, height);
              // Simple bilinear resize
              g.setRenderingHint(RenderingHints.KEY_INTERPOLATION,
                      RenderingHints.VALUE_INTERPOLATION_BILINEAR);
              g.drawImage(srcImage, 0, 0, width, height, null);
              g.dispose();
  
              // Re-encode image to target format
              ByteArrayOutputStream os = new ByteArrayOutputStream();
              ImageIO.write(resizedImage, imageType, os);
              InputStream is = new ByteArrayInputStream(os.toByteArray());
              // Set Content-Length and Content-Type
              ObjectMetadata meta = new ObjectMetadata();
              meta.setContentLength(os.size());
              if (JPG_TYPE.equals(imageType)) {
                  meta.setContentType(JPG_MIME);
              }
              if (PNG_TYPE.equals(imageType)) {
                  meta.setContentType(PNG_MIME);
              }
  
              // Uploading to S3 destination bucket
              System.out.println("Writing to: " + dstBucket + "/" + dstKey);
              s3Client.putObject(dstBucket, dstKey, is, meta);
              System.out.println("Successfully resized " + srcBucket + "/"
                      + srcKey + " and uploaded to " + dstBucket + "/" + dstKey);
              return "Ok";
          } catch (IOException e) {
              throw new RuntimeException(e);
          }
      }
  }
  ```

* Create deployment package

  ```bash
  $> cd lambda-proj
  $> mvn package
  $> tree ./
  ./
  ├── pom.xml
  ├── src
  │   └── main
  │       └── java
  │           └── example
  │               └── S3EventProcessorCreateThumbnail.java
  └── target
      ├── classes
      │   └── example
      │       └── S3EventProcessorCreateThumbnail.class
      ├── lambda-java-example-1.0-SNAPSHOT.jar
      ├── maven-archiver
      │   └── pom.properties
      ├── maven-status
      │   └── maven-compiler-plugin
      │       └── compile
      │           └── default-compile
      │               ├── createdFiles.lst
      │               └── inputFiles.lst
      └── original-lambda-java-example-1.0-SNAPSHOT.jar
  ```

  After we build the project, we will have jar file.

##### Install AWS CLI in linux

* install

```bash
$> curl "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" -o "awscli-bundle.zip"
$> unzip awscli-bundle.zip
$> ./awscli-bundle/install -b ~/bin/aws
```

Add the following line into ```~/.bashrc```.

```bash
export PATH=~/bin:$PATH
```

* access key

  * I already have an access key, so I don't need to create new one
  * If I forget it, I need to re-create a new one via IAM Console

  ```bash
  $> aws configure
  AWS Access Key ID [None]: AKIAIOSFODNN7EXAMPLE
  AWS Secret Access Key [None]: wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
  Default region name [None]: us-west-2
  Default output format [None]: json
  ```

##### Create function

```bash
$> cd target
$> aws lambda create-function --function-name CreateThumbnail \
--zip-file fileb://lambda-java-example-1.0-SNAPSHOT.jar \
--handler example.S3EventProcessorCreateThumbnail --runtime java8 --timeout 30 \
--memory-size 2048 --role arn:aws:iam::xxxxxxxxxxxxxxx:role/lambda-s3-role
```

* --zip-file
  * This is the jar file that we need to upload to AWS Lambda
  * should start with fileb://
* --handler
  * ```example``` is our package name
  * ```S3EventProcessorCreateThumbnail``` is our function name
* --role
  * IAM Console -> lambda-s3-role -> Role ARN

##### Manually test lambda function

* Create a manual event in file ```input.txt```

  ```json
  {
    "Records":[  
      {  
        "eventVersion":"2.0",
        "eventSource":"aws:s3",
        "awsRegion":"us-east-1",
        "eventTime":"1970-01-01T00:00:00.000Z",
        "eventName":"ObjectCreated:Put",
        "userIdentity":{  
          "principalId":"AIDAJDPLRKLG7UEXAMPLE"
        },
        "requestParameters":{  
          "sourceIPAddress":"127.0.0.1"
        },
        "responseElements":{  
          "x-amz-request-id":"C3D13FE58DE4C810",
          "x-amz-id-2":"FMyUVURIY8/IgAtTv8xRjskZQpcIZ9KG4V5Wp6S7S/JRWeUWerMUE5JgHvANOjpD"
        },
        "s3":{  
          "s3SchemaVersion":"1.0",
          "configurationId":"testConfigRule",
          "bucket":{  
            "name":"shellsvirginiabucket",
            "ownerIdentity":{
              "principalId":"A3NL1KOZZKExample"
            },
            "arn":"arn:aws:s3:::shellsvirginabucket"
          },
          "object":{  
            "key":"daao.jpg",
            "size":1024,
            "eTag":"d41d8cd98f00b204e9800998ecf8427e",
            "versionId":"096fKKXTRTtl3on89fVO.nfljtsv6qko"
          }
        }
      }
    ]
  }
  ```

* Trigger lambda function by this manual event

  ```bash
  $> aws lambda invoke --function-name CreateThumbnail --invocation-type Event \
  --payload file://inputfile.txt outputfile.txt
  ```

* Then we can verify in ```shellsvirginiabucket``` that object is resized.

##### Configure S3 to publish event

* Configure permission for s3 to trigger the function

  ```bash
  $> aws lambda add-permission --function-name CreateThumbnail --principal \ s3.amazonaws.com --statement-id some-unique-id --action "lambda:InvokeFunction" \
  --source-arn arn:aws:s3:::shellsvirginiabucket \
  --source-account bucket-owner-account-id
  ```

  * --statement-id
    * Only need to be some unique id.
  * --source-account
    * The account number
    * In AWS management console -> right corner -> user name -> account id

* Verify policy

  ```bash
  $> aws lambda get-policy --function-name function-name
  ```

  * function-name
    * CreateThumbnail 

* Configure notificatin in s3

  * s3 console -> shellsvirginiabucket -> Properties -> Events
  * Name
    * lambda-trigger
  * Events
    * All object create events
  * Send to
    * Lambda function
  * Lambda
    * CreateThumbnail

Now we can upload a file into shellsvirginiabucket and then check resized object.

