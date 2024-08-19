# dagster-spcs

This repository provides a comprehensive guide to deploying Dagster on Snowpark Container Services. It focuses on the deployment process, detailing each step to help you set up and configure Dagster within an SPCS environment.

## Setup

### Create an image repository

An image repository is a storage unit within the Snowflake registry where you store container images. It’s like a table in a database.
We need to create one to store the images for the Dagster components.

```sql
CREATE OR REPLACE IMAGE REPOSITORY {{image_repository_name}}
;

SHOW IMAGE REPOSITORIES
;
```

#### Create a compute pool

A compute pool is a collection of virtual machine nodes Snowflake uses to run Snowpark Container Services. It’s similar to a virtual warehouse, with defined machine types, and minimum and maximum node limits, and is designed to handle varying workloads by scaling as needed.

A compute pool can be created like this:

```sql
CREATE COMPUTE POOL {{compute_pool_name}}
MIN_NODES = 1
MAX_NODES = 1
INSTANCE_FAMILY = CPU_X64_XS
;
```

### Create External Access Integration & Network Rule (Optional)

By default, Snowpark Containers do not have access to the internet. To complete the Dagster University tutorial the container will need access to an external API. This is necessary to create an External Access Integration with a Network Rule.

```sql
CREATE OR REPLACE NETWORK RULE {{network_rule_name}}
MODE = EGRESS
TYPE = HOST_PORT
VALUE_LIST = ('0.0.0.0:443', '0.0.0.0:80')
;

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION {{external_access_integration_name}}
ALLOWED_NETWORK_RULES = ({{network_rule_name}})
ENABLED = true
;
```

### Create an internal Stage

Create a [Snowflake Internal Stage](https://docs.snowflake.com/en/sql-reference/sql/create-stage) that will serve as the volume for the code locations container and will host the Dagster definitions.

```sql
CREATE STAGE {{database}}.{{schema}}.{{internal_stage_name}} 
DIRECTORY = ( ENABLE = true )
;
```

Now upload the [dagster_univeristy](dagster_univeristy) and [data](data) folders in the stage. You can also upload your dagster project files.

### Define the name of the services

If you are familiar with Dagster, you may know that the architecture has three long-running services and a database.
We will deploy each of these as Snowflake services.

The syntax to create a Snowflake service is the following:

```sql
CREATE SERVICE {{service_name}}
IN COMPUTE POOL {{compute_pool_name}}
MIN_INSTANCES=1
MAX_INSTANCES=1
EXTERNAL_ACCESS_INTEGRATIONS = ({{external_access_integration_name}})
```

When a service is created, Snowflake assigns it a DNS with the following structure:

```txt
{{service-name}}.{{schema-name}}.{{db-name}}.snowflakecomputing.internal
```

Note that Snowflake will replace the underscores in your `service_name` with dashes when creating the DNS. So, if your service name is something like `my_cool_service` the DNS will look like `my-cool-service. schema.database.snowflakecomputing.internal`. If you have doubts about the Service's DNS, you can always check it with the following query:

```sql
DESCRIBE SERVICE my_cool_service
;
```

I suggest using these names for the services:

```Python
# Services
database_service_name = "DAGSTER_DATABASE_SERVICE"
code_location_service_name = "DAGSTER_CODE_LOCATION_SERVICE"
web_server_service_name = "DAGSTER_WEB_SERVER_SERVICE"
daemon_service_name = "DAGSTER_DAEMON_SERVICE"
```

With the service names defined, go to [dagster.yaml](dagster.yaml) and verify that the Postgres-related `hostnames` are like this:

```txt
dagster-database-service.schema.database.snowflakecomputing.internal
```

 Also, go to [workspace.yaml](workspace.yaml) and verify that the grpc_server `hosts` are like this:

```txt
dagster-code-location-service.schema.database.snowflakecomputing.internal
```

### Build & Push the images to the Snowflake Repository

Go to the [build_and_push.sh](build_and_push.sh) file and replace the `IMAGE_REGISTRY` & `IMAGE_REPO_URL` with your account values.
If you have doubts about these values use `SHOW IMAGE REPOSITORIES;` to check them.

Now run the [build_and_push.sh](build_and_push.sh) script:

```sh
bash build_and_push.sh
```

Check that the images are loaded in the repo with the following command:

```sql
SHOW IMAGES IN IMAGE REPOSITORY {{image_repository}}
;
```

### Create the services

Now you can create the services. I recommend running the following commands using Snowflake notebooks to take advantage of the Jinja templating features by defining all the variables at the beginning of the notebook in a Python cell:

```python
# Image and pool
image_repository = "DAGSTER_UNIVERSITY_REPO"
compute_pool_name = "dagster_compute_pool"

# Services
database_service_name = "DAGSTER_DATABASE_SERVICE"
code_location_service_name = "DAGSTER_CODE_LOCATION_SERVICE"
web_server_service_name = "DAGSTER_WEB_SERVER_SERVICE"
daemon_service_name = "DAGSTER_DAEMON_SERVICE"

# Networks
network_rule_name = "dagster_university_network_rule"
external_access_integration_name = "dagster_university_EAI"

# Stages
stage_name = "DAGSTER_UNIVERSITY"
```

Also, have in mind that the `ACCOUNTADMIN`, `ORGADMIN` and `SECURITYADMIN` roles cannot create services.

#### Database Service

To create the database service run the following query:

***
Note: You can check the `postgres_image_path` value with the `SHOW IMAGES IN IMAGE REPOSITORY {{image_repository}};` query.
***

```sql
CREATE SERVICE {{database_service_name}}
IN COMPUTE POOL {{compute_pool_name}}
MIN_INSTANCES=1
MAX_INSTANCES=1
EXTERNAL_ACCESS_INTEGRATIONS = ({{external_access_integration_name}})
FROM SPECIFICATION $$
spec:
 containers:
 - name: postgres
    image: {{postgres_image_path}}
 env:
 POSTGRES_USER: "postgres_user"
 POSTGRES_PASSWORD: "postgres_password"
 POSTGRES_DB: "postgres_db"

  endpoint:
 - name: postgres-endpoint
 port: 5432
 public: true
 $$
;
```

#### Code Location Service

To create the code location service run the following query:

***
Note:

- You can check the `user_code_image_path` value with the `SHOW IMAGES IN IMAGE REPOSITORY {{image_repository}};` query.

- This step is assuming that you loaded the `dagster_university` folder in the stage. If you loaded a different folder, change the folder name in the `command` section of the `SPECIFICATION`.

***

```sql
CREATE SERVICE {{code_location_service_name}}
IN COMPUTE POOL {{compute_pool_name}}
MIN_INSTANCES=1
MAX_INSTANCES=1
EXTERNAL_ACCESS_INTEGRATIONS = ({{external_access_integration_name}})
FROM SPECIFICATION $$
spec:
 containers:
 - name: user-code-container
    image: {{user_code_image_path}}
 volumeMounts:
 - name: user-code
 mountPath: /opt/dagster/app/
 env:
 DAGSTER_POSTGRES_USER: "postgres_user"
 DAGSTER_POSTGRES_PASSWORD: "postgres_password"
 DAGSTER_POSTGRES_DB: "postgres_db"
 command:
 - dagster
 - api
 - grpc
 - -h
 - 0.0.0.0
 - -p
 - "4000"
 - -m
 - dagster_university

  endpoint:
 - name: code-location-endpoint
 port: 4000
 public: true
      
 volumes:
 - name: user-code
 source: "@{{stage_name}}"

 $$
;
```

#### Web Server Service

To create the web server service run the following query:

***
Note:

- You can check the `web_server_image_path` value with the `SHOW IMAGES IN IMAGE REPOSITORY {{image_repository}};` query.

- Make sure that you are using the right `postgres_service_dns`. the `postgres_service_dns` value with the `DESCRIBE SERVICE {{database_service_name}};` query after creating the `database_service_name` service.

***

```sql
CREATE SERVICE {{web_server_service_name}}
IN COMPUTE POOL {{compute_pool_name}}
MIN_INSTANCES=1
MAX_INSTANCES=1
EXTERNAL_ACCESS_INTEGRATIONS = ({{external_access_integration_name}})
FROM SPECIFICATION $$
spec:
 containers:
 - name: webserver-container
    image: {{web_server_image_path}}
 command:
 - dagster-webserver
 - -h
 - "0.0.0.0"
 - -p
 - "3000"
 - -w
 - workspace.yaml
 env:
 DAGSTER_POSTGRES_HOST: {{postgres_service_dns}}
 DAGSTER_POSTGRES_PORT: "5432"
 DAGSTER_POSTGRES_USER: "postgres_user"
 DAGSTER_POSTGRES_PASSWORD: "postgres_password"
 DAGSTER_POSTGRES_DB: "postgres_db"

  endpoint:
 - name: dagster-endpoint
 port: 3000
 public: true

 $$
;
```

#### Daemon Service

To create the web server service run the following query:

***
Note:

- You can check the `daemon_image_path` value with the `SHOW IMAGES IN IMAGE REPOSITORY {{image_repository}};` query.

- Make sure that you are using the right `postgres_service_dns`. the `postgres_service_dns` value with the `DESCRIBE SERVICE {{database_service_name}};` query after creating the `database_service_name` service.

***

```sql
CREATE SERVICE {{daemon_service_name}}
IN COMPUTE POOL {{compute_pool_name}}
MIN_INSTANCES=1
MAX_INSTANCES=1
EXTERNAL_ACCESS_INTEGRATIONS = ({{external_access_integration_name}})
FROM SPECIFICATION $$
spec:
 containers:
 - name: daemon-container
    image: {{daemon_image_path}}
 command:
 - dagster-daemon
 - run
 env:
 DAGSTER_POSTGRES_HOST: {{postgres_service_dns}}
 DAGSTER_POSTGRES_PORT: "5432"
 DAGSTER_POSTGRES_USER: "postgres_user"
 DAGSTER_POSTGRES_PASSWORD: "postgres_password"
 DAGSTER_POSTGRES_DB: "postgres_db"

 $$
;
```

### Check that everything is running

You can check if the created services are running with these queries:

```sql
DESCRIBE SERVICE {{database_service_name}};
DESCRIBE SERVICE {{code_location_service_name}};
DESCRIBE SERVICE {{web_server_service_name}};
DESCRIBE SERVICE {{daemon_service_name}};
```

It is also possible to get more details about the services with this query:

```sql
SELECT PARSE_JSON(SYSTEM$GET_SERVICE_STATUS('{{web_server_service_name}}'));
```

And, if something fails, you can check the service logs with this query:

```sql
SELECT SYSTEM$GET_SERVICE_LOGS('{{web_server_service_name}}', 0, 'webserver-container', 20)
;
```

### Costs

Have in mind that this implementation is a bit expensive (around 6 credits a day). You can explore the daily costs of the running services with this query:

```sql
select
    usage_date,
    service_type,
    sum(credits_used)
from METERING_DAILY_HISTORY
where service_type = 'SNOWPARK_CONTAINER_SERVICES'
group by 1, 2
order by 1 desc, 2 asc
;
```
