# AWS Lambda Custom Runtime

I record my experience to learn the tutorial of how we use cpp leveraging aws custom runtime interface. I based on this [post](https://aws.amazon.com/blogs/compute/introducing-the-c-lambda-runtime/).

#### Hello World

###### Prerequisite

We need c++ 11 compiler (gcc 5.x or later) and cmake (v.3.5 or later).

```bash
$> g++ --version
g++ (Ubuntu 5.4.0-6ubuntu1~16.04.11) 5.4.0 20160609
Copyright (C) 2015 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
$> cmake --version
cmake version 3.5.1
$> sudo apt-get install libcurl4-openssl-dev
```

Then we need to download the source code of aws-lambda-cpp, which is the aws lambda runtime interface.

```bash
$> sudo apt-get install libcurl4-openssl-dev
$> git clone https://github.com/awslabs/aws-lambda-cpp.git
$> cd aws-lambda-cpp/
$> mkdir build
$> cd build/
$> cmake .. -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
-DCMAKE_INSTALL_PREFIX=/home/lixl/LEARN/AWSLambda/out
$> make && make install
```

Then the runtime library is installed as the static library under ```/home/lixl/LEARN/AWSLambda/out```.

###### Create c++ function

* new directory for the project

  ```bash
  $> mkdir hello-cpp-world
  $> cd hello-cpp-world
  ```

* main.cpp

  ```c++
  #include <aws/lambda-runtime/runtime.h>
  
  using namespace aws::lambda_runtime;
  
  invocation_response my_handler(invocation_request const& request) {
    return invocation_response::success("Hello, World!", "application/json");
  }
  
  int main() {      
    run_handler(my_handler);
    return 0;      
  }
  ```

* CMakeList.txt

  ```c++
  cmake_minimum_required(VERSION 3.5)
  set(CMAKE_CXX_STANDARD 11)
  project(hello LANGUAGES CXX)
  
  find_package(aws-lambda-runtime REQUIRED)
  add_executable(${PROJECT_NAME} main.cpp)
  target_link_libraries(${PROJECT_NAME} PUBLIC AWS::aws-lambda-runtime)
  aws_lambda_package_target(${PROJECT_NAME})
  ```

* Build

  ```bash
  $> mkdir build
  $> cd build
  $> cmake .. -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH=/home/lixl/LEARN/AWSLambda/out
  $> make
  $> ls
  CMakeCache.txt  CMakeFiles  cmake_install.cmake  hello  Makefile
  ```

  We have an executable file ```hello``` under this directory.

* Package with all dependencies

  ```bash
  $> make aws-lambda-package-hello
  ```

  Then there is a ```hello.zip``` .

###### Create lambda function

We run the following command to create the function:

```bash
$> aws lambda create-function --function-name hello-world \
--role arn:aws:iam::xxxxxxxxxxxx:role/lambda-s3-role \
--runtime provided --timeout 30 --memory-size 2048 --handler hello \
--zip-file fileb://hello.zip
```

###### Invoke the function using aws cli

```bash
$> aws lambda invoke --function-name hello-world --payload '{ }' output.txt
$> cat output.txt
Hello, World!
```

This call will invoke the lambda function, and the output is in output.txt.

#### File Processing with AWS S3

* Prerequisite

  ```bash
  $> sudo apt install zlib1g-dev
  $> sudo apt install libssl-dev
  ```

* Build aws-sdk-cpp

  ```bash
  $> git clone https://github.com/aws/aws-sdk-cpp.git
  $> cd aws-sdk-cpp
  $> mkdir build
  $> cd build
  $> cmake .. -DBUILD_ONLY=s3 -DBUILD_SHARED_LIBS=OFF -DENABLE_UNITY_BUILD=ON \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/home/lixl/LEARN/AWSLambda/out
  $> make
  $> make install
  ```

* create directory for cpp-encoder-directory

  ```bash
  $> mkdir cpp-encoder-example
  $> cd cpp-encoder-example
  ```

* main.cpp

  ```c++
  #include <aws/core/Aws.h>
  #include <aws/core/utils/logging/LogLevel.h>
  #include <aws/core/utils/logging/ConsoleLogSystem.h>
  #include <aws/core/utils/logging/LogMacros.h>
  #include <aws/core/utils/json/JsonSerializer.h>
  #include <aws/core/utils/HashingUtils.h>
  #include <aws/core/platform/Environment.h>
  #include <aws/core/client/ClientConfiguration.h>
  #include <aws/core/auth/AWSCredentialsProvider.h>
  #include <aws/s3/S3Client.h>
  #include <aws/s3/model/GetObjectRequest.h>
  #include <aws/lambda-runtime/runtime.h>
  #include <iostream>
  #include <memory>
  
  using namespace aws::lambda_runtime;
  
  std::string download_and_encode_file(
      Aws::S3::S3Client const& client,
      Aws::String const& bucket,
      Aws::String const& key,
      Aws::String& encoded_output);
  
  std::string encode(Aws::String const& filename, Aws::String& output);
  char const TAG[] = "LAMBDA_ALLOC";
  
  static invocation_response my_handler(invocation_request const& req, Aws::S3::S3Client const& client)
  {
      using namespace Aws::Utils::Json;
      JsonValue json(req.payload);
      if (!json.WasParseSuccessful()) {
          return invocation_response::failure("Failed to parse input JSON", "InvalidJSON");
      }
  
      auto v = json.View();
  
      if (!v.ValueExists("s3bucket") || !v.ValueExists("s3key") || !v.GetObject("s3bucket").IsString() ||
          !v.GetObject("s3key").IsString()) {
          return invocation_response::failure("Missing input value s3bucket or s3key", "InvalidJSON");
      }
  
      auto bucket = v.GetString("s3bucket");
      auto key = v.GetString("s3key");
  
      AWS_LOGSTREAM_INFO(TAG, "Attempting to download file from s3://" << bucket << "/" << key);
  
      Aws::String base64_encoded_file;
      auto err = download_and_encode_file(client, bucket, key, base64_encoded_file);
      if (!err.empty()) {
          return invocation_response::failure(err, "DownloadFailure");
      }
  
      return invocation_response::success(base64_encoded_file, "application/base64");
  }
  
  std::function<std::shared_ptr<Aws::Utils::Logging::LogSystemInterface>()> GetConsoleLoggerFactory()
  {
      return [] {
          return Aws::MakeShared<Aws::Utils::Logging::ConsoleLogSystem>(
              "console_logger", Aws::Utils::Logging::LogLevel::Trace);
      };
  }
  
  int main()
  {
      using namespace Aws;
      SDKOptions options;
      options.loggingOptions.logLevel = Aws::Utils::Logging::LogLevel::Trace;
      options.loggingOptions.logger_create_fn = GetConsoleLoggerFactory();
      InitAPI(options);
      {
          Client::ClientConfiguration config;
          config.region = Aws::Environment::GetEnv("AWS_REGION");
          config.caFile = "/etc/pki/tls/certs/ca-bundle.crt";
  
          auto credentialsProvider = Aws::MakeShared<Aws::Auth::EnvironmentAWSCredentialsProvider>(TAG);
          S3::S3Client client(credentialsProvider, config);
          auto handler_fn = [&client](aws::lambda_runtime::invocation_request const& req) {
              return my_handler(req, client);
          };
          run_handler(handler_fn);
      }
      ShutdownAPI(options);
      return 0;
  }
  
  std::string encode(Aws::IOStream& stream, Aws::String& output)
  {
      Aws::Vector<unsigned char> bits;
      bits.reserve(stream.tellp());
      stream.seekg(0, stream.beg);
  
      char streamBuffer[1024 * 4];
      while (stream.good()) {
          stream.read(streamBuffer, sizeof(streamBuffer));
          auto bytesRead = stream.gcount();
  
          if (bytesRead > 0) {
              bits.insert(bits.end(), (unsigned char*)streamBuffer, (unsigned char*)streamBuffer + bytesRead);
          }
      }
      Aws::Utils::ByteBuffer bb(bits.data(), bits.size());
      output = Aws::Utils::HashingUtils::Base64Encode(bb);
      return {};
  }
  
  std::string download_and_encode_file(
      Aws::S3::S3Client const& client,
      Aws::String const& bucket,
      Aws::String const& key,
      Aws::String& encoded_output)
  {
      using namespace Aws;
  
      S3::Model::GetObjectRequest request;
      request.WithBucket(bucket).WithKey(key);
  
      auto outcome = client.GetObject(request);
      if (outcome.IsSuccess()) {
          AWS_LOGSTREAM_INFO(TAG, "Download completed!");
          auto& s = outcome.GetResult().GetBody();
          return encode(s, encoded_output);
      }
      else {
          AWS_LOGSTREAM_ERROR(TAG, "Failed with error: " << outcome.GetError());
          return outcome.GetError().GetMessage();
      }
  }
  ```

* build

  ```bash
  $> mkdir build
  $> cd build
  $> cmake .. -DCMAKE_BUILD_TYPE=Release 
  -DCMAKE_PREFIX_PATH=/home/lixl/LEARN/AWSLambda/out
  $> make
  $> make aws-lambda-package-encoder
  ```

  Now we will have ```encoder.zip``` under ```build``` directory.

* create function

  ```bash
  $> aws lambda create-function --function-name encode-file \
  --role arn:aws:iam::xxxxxxxxxxxx:role/lambda-s3-role --runtime provided \
  --timeout 30 --memory-size 2048 --handler encoder --zip-file fileb://encoder.zip
  ```

* invoke function

  ```bash
  $> aws lambda invoke --function-name encode-file \
  --payload '{"s3bucket": "encoderbucket", "s3key":"daao.jpg" }' base64_image.txt
  ```

  Then lambda function is invoked. It will download the file ```daao.jpg``` from my bucket ```encoderbucket``` and then encode it into the file ```base64_image.txt``` at my local file system.

