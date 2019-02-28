#!/bin/bash -x

#
# ------------------------------------------------------------------
#         Signal SUCCESS OR FAILURE of Wait Handle
# ------------------------------------------------------------------

source /root/install/config

SCRIPT_DIR="/root/install"
if [ -z "${INSTALL_LOG_FILE}" ] ; then
    INSTALL_LOG_FILE=${SCRIPT_DIR}/install.log
fi

log() {
    echo $* 2>&1 | tee -a ${INSTALL_LOG_FILE}
}

usage() {
    cat <<EOF
    Usage: $0 [0 or 1] #1=FAILURE 0=SUCCESS
EOF
    exit 0
}

set_install_cfn() {
#install the cfn helper scripts
	
	cd /tmp
	wget https://s3.amazonaws.com/cloudformation-examples/aws-cfn-bootstrap-latest.tar.gz
	gzip -df aws-cfn-bootstrap-latest.tar.gz
	tar -xvf aws-cfn-bootstrap-latest.tar
    ln -s /tmp/aws-cfn-bootstrap-1.4 /tmp/aws
    chmod -R 755 /tmp/aws-cfn-bootstrap-1.4

	yum install -y epel-release
    yum install -y python-pip

	pip install --upgrade setuptools

}


# ------------------------------------------------------------------
#          Read all inputs
# ------------------------------------------------------------------


[[ $# -ne 2 ]] && usage;



set_install_cfn


export PYTHONPATH=/tmp/aws:$PYTHONPATH

SIGNAL="$1"
MSG="$2"

log $(date) signal-final-status.sh

if [ "${SIGNAL}" == "0" ]; then
   /tmp/aws/bin/cfn-signal -e "$SIGNAL" -r "$MSG" "${WAITFORSDHINSTALLWAITHANDLE}"
else
   /tmp/aws/bin/cfn-signal -e "$SIGNAL" -r "$MSG" "${WAITFORSDHINSTALLWAITHANDLE}"
fi

log $(date) END signal-final-staus.sh


exit 0