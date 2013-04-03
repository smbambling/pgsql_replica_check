#!/bin/bash
# Check against a list of nodes to determine if it has the furthest ahead xlog position
# Also checks if there are multiple nodes with the same xlog location to see which has the least replay lag


NODENAME=`uname -n | tr '[A-Z]' '[a-z]'`
CHECK_XLOG_LOC_SQL="select xlog_location_numeric()"
CHECK_REPLAY_LAG_SQL="select replay_lag_bytes()"

get_xlog_location() {
    output=`su postgres -c "psql -U postgres -h $1 -Atc \"${CHECK_XLOG_LOC_SQL}\""`
    rc=$?
    if [ $rc -ne 0 ]; then
        #ocf_log err "Can't get $1 xlog location."
        return 1
    fi

    echo $output
}

get_replay_lag() {
    output=`su postgres -c "psql -U postgres -h $1 -Atc \"${CHECK_REPLAY_LAG_SQL}\""`

    rc=$?
    if [ $rc -ne 0 ]; then
        #ocf_log err "Can't get $1 replay lag."
        return 1
    fi

    echo $output
}

get_online_nodes() {
    #NODE_LIST=`crm_mon -1 | grep "Online:" | sed -e "s/.*\[\(.*\)\]/\1/" | sed 's/ //'`
    NODE_LIST="node1 node2 node3"
}

get_xlog_locations() {
    # Get list of Online Nodes
    get_online_nodes
    
    # Get current xlog location for Online Nodes
    xlogloc=()
    xlognodes=()

    for node in ${NODE_LIST}; do
        location=`get_xlog_location ${node}` || return 1
    xlogloc+=(${location})
    xlognodes+=(${node})
    done
}

get_furthest_replicas() {
    
    get_xlog_locations

    # Determine what replica is furthest ahead
    furthestxlog=${xlogloc[0]}

    for i in "${!xlogloc[@]}"; do
        if [[ ${xlogloc[$i]} > ${furthestxlog} ]]; then
            furthestxlog=${xlogloc[$i]}
        fi
    done

    # Check to see if there is more then 1 node with the same furthest ahead log position
    fars=()
    for i in "${!xlogloc[@]}"; do
        if [[ "${xlogloc[$i]}" == "${furthestxlog}" ]]; then
            fars+=(${xlognodes[$i]})
        fi
    done

    # Select the nodes with the furthest ahead xlog position
    furthestreplicas=${fars[@]}
}

get_least_replay_lag_replicas() {

    get_furthest_replicas

    # Get current replay log on nodes with furthest ahead log position
    replayloc=()
    replaynodes=()

    for node in ${furthestreplicas}; do
        location=`get_replay_lag ${node}` || return 1
        replayloc+=(${location})
        replaynodes+=(${node})
    done

    # Determine what replica has the least replay lag
    furthestreplay=${replayloc[0]}

    for i in "${!replayloc[@]}"; do
        if [[ "${replayloc[$i]}" < "${furthestreplay}" ]]; then
            furthestreplay=${replayloc[$i]}
        fi
    done

    # Check to see if there is more then 1 more with the same replay lag
    newfars=()
    for i in "${!replayloc[@]}"; do
        if [[ "${replayloc[$i]}" = ${furthestreplay}  ]]; then
        newfars+=(${replaynodes[$i]})
        fi
    done

    # Check if the current promoted node has the lastest xlog locatin and has the least replay lag
    for i in "${!newfars[@]}"; do
        if [[ "${newfars[$i]}" = ${NODENAME} ]]; then
            echo "Current Node is up to date"
            return 1
        fi
    done
    
}
get_least_replay_lag_replicas


