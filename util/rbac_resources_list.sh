#!/bin/bash
set -eo pipefail

# list all the kubernetes rbac resources/sub-resources and associated Verbs, Kind
# Usage: set properly your kube context and run the script.
# exemple of output: 
# API                                     Resource                                                    Verb                                                        Namespaced             Kind
# bindings                                create                                                      true                                                        Binding                
# componentstatuses                       get,list                                                    false                                                       ComponentStatus        
# configmaps                              create,delete,deletecollection,get,list,patch,update,watch  true                                                        ConfigMap              

# Generate a UUID for the tmp output file
ftmp=/tmp/list_rbac_resources_$(uuidgen)

url=$(kubectl config view --minify --output jsonpath="{.clusters[*].cluster.server}")
cacert=$(kubectl config view --minify --output jsonpath="{.clusters[*].cluster.certificate-authority}")
token=$(kubectl config view --minify --output jsonpath="{.users[*].user.auth-provider.config.id-token}")

# Get the list of APIs
APIS=$(curl --header "Authorization: Bearer $token" --cacert $cacert -s $url/apis | jq -r '[.groups | .[].name] | join(" ")')

# Add header to tmp output file
echo "API Resource Verb Namespaced Kind" >> ${ftmp}

# Get the list of resources/sub-resources from the core API
curl --header "Authorization: Bearer $token" --cacert $cacert -s $url/api/v1 | jq -r --arg api "$api" '.resources | .[] | "\($api) \(.name) \(.verbs | join(",")) \(.namespaced) \(.kind)"' >> ${ftmp}

# Get the list of resources/sub-resources from the other APIs
for api in $APIS; do
    version=$(curl --header "Authorization: Bearer $token" --cacert $cacert -s $url/apis/$api | jq -r '.preferredVersion.version')
    curl --header "Authorization: Bearer $token" --cacert $cacert -s $url/apis/$api/$version | jq -r --arg api "$api" '.resources | .[]? | "\($api) \(.name) \(.verbs | join(",")) \(.namespaced) \(.kind)"' >> ${ftmp}
done

# Print the list of resources/sub-resources using the column command
column -t ${ftmp}

# Remove the tmp output file
rm -rf ${ftmp}
