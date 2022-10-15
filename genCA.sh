#!/usr/bin/env bash

# Variables
PATH_INVENTORY='./inventory.json'
PATH_CA='./ca'
PATH_TEMP='temp'

NAME_ROOT='root'
PATH_ROOT_CNF='root-self-signed.cnf'
SIZE_ROOT_KEY='2048'



# User-defined functions
# Creating
function FolderBuilder() { 
    echo "${1}"
    if [[ -d  "${PATH_CA}/${1}" ]]; then
        :
    else
        mkdir -p "${PATH_CA}/${1}"
    fi
}

function CABuilder() {
    echo "$(date) Creating the Certification Authority"
        if [[ -d  "${PATH_CA}/${NAME_ROOT}" ]]; then
            :
        else
            rm -r "${PATH_CA}"
            mkdir -p "${PATH_CA}/${NAME_ROOT}"
            rm -r ./demoCA
            mkdir -p ./demoCA/newcerts
            #touch "${PATH_CA}/${NAME_ROOT}"/demoCA/newcerts
            touch ./demoCA/index.txt
            touch ./demoCA/index.txt.attr
            echo "unique_subject = no" > ./demoCA/index.txt.attr
            touch ./demoCA/serial.txt
            echo 1000 > ./demoCA/serial.txt

        fi  
        cd "${PATH_CA}/${NAME_ROOT}"   
        openssl genrsa -out "${NAME_ROOT}".pem "${SIZE_ROOT_KEY}"
        echo "======================================================================================================================================"
        echo "$(date) Generating Self Signed Root Certificate"
        echo "======================================================================================================================================"
        openssl req -x509 -new -nodes -key "${NAME_ROOT}".pem -out "${NAME_ROOT}".crt -config "../../${PATH_ROOT_CNF}"
        cd ../../
}


function CertSigner() {
    
    # WIP: adding DNS to avoid -skip-verify


        #echo " ${1} ${3} ${BITS} ${COUNTRY} ${STATE} ${CITY} ${FQDN} ${ORG}"
        echo "[ req ]" >> ./${PATH_CA}/${1}/${1}-cert-request.cnf
        echo "default_bits       = ${5}" >> ./${PATH_CA}/${1}/${1}-cert-request.cnf
        echo "distinguished_name = req_distinguished_name" >> ./${PATH_CA}/${1}/${1}-cert-request.cnf
        if [[  $(echo "${3}") != "client"  ]]; then echo "req_extensions     = req_ext" >> ./${PATH_CA}/${1}/${1}-cert-request.cnf; else :; fi
            


        echo "prompt             = no" >> ./${PATH_CA}/${1}/${1}-cert-request.cnf
        echo "[ req_distinguished_name ]" >> ./${PATH_CA}/${1}/${1}-cert-request.cnf
        echo "countryName                 = ${6}" >> ./${PATH_CA}/${1}/${1}-cert-request.cnf
        echo "stateOrProvinceName         = ${7}" >> ./${PATH_CA}/${1}/${1}-cert-request.cnf
        echo "localityName               = ${8}" >> ./${PATH_CA}/${1}/${1}-cert-request.cnf
        echo "organizationName           = ${9}" >> ./${PATH_CA}/${1}/${1}-cert-request.cnf
        echo "organizationalUnitName           = ${10}" >> ./${PATH_CA}/${1}/${1}-cert-request.cnf
        echo "commonName                 = ${11}" >> ./${PATH_CA}/${1}/${1}-cert-request.cnf 
        if [[  $(echo "${3}") != "client"  ]]; then 
        echo "[ req_ext ]" >> ./${PATH_CA}/${1}/${1}-cert-request.cnf
        echo "subjectAltName = IP:${IP}" >> ./${PATH_CA}/${1}/${1}-cert-request.cnf; else :; fi     



    echo "======================================================================================================================================"
    echo "$(date) Creating the Private key for Server and Clients"
    echo "======================================================================================================================================"
    openssl genrsa -out ./${PATH_CA}/${1}/"${1}"-key.pem "${SIZE_ROOT_KEY}" 
    echo "======================================================================================================================================"
    echo "$(date) Creating a Certificate Signing Request (CSR) for ${1}"
    echo "======================================================================================================================================"
    openssl req -out ./${PATH_CA}/${1}/"${1}"-csr.pem -key ./${PATH_CA}/${1}/"${1}"-key.pem -new -config ./${PATH_CA}/${1}/${1}-cert-request.cnf
    echo "======================================================================================================================================"
    echo "$(date) Sign the CSR previously generated for ${1} with values: ${2}  ${4} ${5} ${6} ${7} ${8}"
    echo "======================================================================================================================================"
    # openssl ca -batch -out ./ca/leaf1/laeaf1-pbcert.pem -keyfile ./ca/root/root.pem  -cert ./ca/root/root.crt
    openssl ca -batch -out ./${PATH_CA}/${1}/"${1}".pem -keyfile ./${PATH_CA}/${NAME_ROOT}/"${NAME_ROOT}".pem -days 1024 -cert ./${PATH_CA}/${NAME_ROOT}/"${NAME_ROOT}".crt -infiles ./${PATH_CA}/${1}/"${1}"-csr.pem

}




# Body

# Creating the Root Certification authority
CABuilder

# Parsing the .CNF file to generate conf files for each device
DEVICE_NUMBER=$(jq '.[] | length' ${PATH_INVENTORY})

while read LINE; do    
    BITS="2048"

    if [[ $(echo "${LINE}" | awk '/countryName/ {print $1}') == "countryName" ]]; then COUNTRY=$(echo "${LINE}" | awk '/countryName/ {print $3}'); else :; fi
    if [[ $(echo "${LINE}" | awk '/stateOrProvinceName/ {print $1}') == "stateOrProvinceName" ]]; then STATE=$(echo "${LINE}" | awk '/stateOrProvinceName/ {print $3}'); else :; fi
    if [[ $(echo "${LINE}" | awk '/localityName/ {print $1}') == "localityName" ]]; then CITY=$(echo "${LINE}" | awk '/localityName/ {print $3}'); else :; fi
    if [[ $(echo "${LINE}" | awk '/organizationName/ {print $1}') == "organizationName" ]]; then ORG=$(echo "${LINE}" | awk '/organizationName/ {print $3}'); else :; fi
    if [[ $(echo "${LINE}" | awk '/organizationalUnitName/ {print $1}') == "organizationalUnitName" ]]; then BU=$(echo "${LINE}" | awk '/organizationalUnitName/ {print $3}'); else :; fi
    if [[ $(echo "${LINE}" | awk '/commonName/ {print $1}') == "commonName" ]]; then FQDN=$(echo "${LINE}" | awk '/commonName/ {print $3}'); else :; fi
done < ${PATH_ROOT_CNF}

echo "======================================================================================================================================"
echo "Parsing the the ${PATH_INVENTORY} and ${PATH_ROOT_CNF} Files"
echo "======================================================================================================================================"
    


# Reading the Inventory and parsing variables
for ((ID = 0; ID < ${DEVICE_NUMBER}; ID ++)); do
    # base cmd:
    # cat inventory.json | jq ".devices[0].hostname"
    HOST=$(cat "${PATH_INVENTORY}" | jq ".devices[${ID}].hostname" | sed -e 's/"//g')
    IP=$(cat "${PATH_INVENTORY}" | jq ".devices[${ID}].ip_address" | sed -e 's/"//g')
    KIND=$(cat "${PATH_INVENTORY}" | jq ".devices[${ID}].kind" | sed -e 's/"//g')

    FolderBuilder "${HOST}" 
    CertSigner "${HOST}" "${IP}" "${KIND}" "${PATH_CA}" "${BITS}" "${COUNTRY}" "${STATE}" "${CITY}" "${ORG}" "${BU}" "${FQDN}" 
done


