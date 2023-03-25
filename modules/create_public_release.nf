process create_public_release {
    debug true
    container 'sagebionetworks/genie:latest'
    secret 'SYNAPSE_AUTH_TOKEN'

    input:
    val release
    val seq
    val production

    output:
    stdout

    script:
    if (production) {
        """
        python3 /root/Genie/bin/consortium_to_public.py \
        $seq \
        /root/cbioportal \
        $release
        """
    }
    else {
        """
        python3 /root/Genie/bin/consortium_to_public.py \
        $seq \
        /root/cbioportal \
        $release \
        --test
        """
    }
}
