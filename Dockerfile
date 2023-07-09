FROM golang:1.19 AS go_builder
WORKDIR /go/src/github.com/percona/percona-xtradb-cluster-operator/src

RUN export GO111MODULE=off; \
    go get k8s.io/apimachinery/pkg/util/sets; \
    curl -Lf -o /go/src/github.com/percona/percona-xtradb-cluster-operator/src/peer-list.go https://raw.githubusercontent.com/percona/percona-xtradb-cluster-operator/main/cmd/peer-list/main.go; \
    go build peer-list.go

FROM redhat/ubi8-minimal

LABEL org.opencontainers.image.authors="info@percona.com"

ENV PXC_VERSION 8.0.32-24.2
ENV PXC_REPO release
ENV OS_VER el8
ENV FULL_PERCONA_XTRADBCLUSTER_VERSION "$PXC_VERSION.$OS_VER"

# check repository package signature in secure way
RUN set -ex; \
    export GNUPGHOME="$(mktemp -d)"; \
    gpg --batch --keyserver keyserver.ubuntu.com --recv-keys 76FD3DB13AB67410B89DB10E82562EA9AD986DA3 430BDF5C56E7C94E848EE60C1C4CBDCDCD2EFD2A 99DB70FAE1D7CE227FB6488205B555B38483C65D 94E279EB8D8F25B21810ADF121EA45AB2F86D6A1; \
    gpg --batch --export --armor 430BDF5C56E7C94E848EE60C1C4CBDCDCD2EFD2A > ${GNUPGHOME}/RPM-GPG-KEY-Percona; \
    gpg --batch --export --armor 99DB70FAE1D7CE227FB6488205B555B38483C65D > ${GNUPGHOME}/RPM-GPG-KEY-centosofficial; \
    gpg --batch --export --armor 94E279EB8D8F25B21810ADF121EA45AB2F86D6A1 > ${GNUPGHOME}/RPM-GPG-KEY-EPEL-8; \
    gpg --batch --export --armor 76FD3DB13AB67410B89DB10E82562EA9AD986DA3 > ${GNUPGHOME}/RPM-GPG-KEY-oracle; \
    rpmkeys --import ${GNUPGHOME}/RPM-GPG-KEY-Percona ${GNUPGHOME}/RPM-GPG-KEY-centosofficial ${GNUPGHOME}/RPM-GPG-KEY-EPEL-8 ${GNUPGHOME}/RPM-GPG-KEY-oracle; \
    #microdnf -y update; \
    microdnf install -y findutils; \
    curl -Lf -o /tmp/percona-release.rpm https://repo.percona.com/yum/percona-release-latest.noarch.rpm; \
    rpmkeys --checksig /tmp/percona-release.rpm; \
    rpm -i /tmp/percona-release.rpm; \
    rm -rf "$GNUPGHOME" /tmp/percona-release.rpm; \
    rpm --import /etc/pki/rpm-gpg/PERCONA-PACKAGING-KEY

RUN set -ex; \
    curl -Lf -o /tmp/libev.rpm http://vault.centos.org/centos/8/AppStream/x86_64/os/Packages/libev-4.24-6.el8.x86_64.rpm; \
    curl -Lf -o /tmp/pv.rpm http://download.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/p/pv-1.6.6-7.el8.x86_64.rpm; \
    rpmkeys --checksig /tmp/libev.rpm /tmp/pv.rpm; \
    rpm -i /tmp/libev.rpm /tmp/pv.rpm; \
    rm -rf /tmp/libev.rpm /tmp/pv.rpm

RUN set -ex; \
    #percona-release setup -y ps-80; \
    rpm -e --nodeps tzdata; \
    microdnf install -y \
        jemalloc \
        numactl-libs \
        jq \
        socat \
        krb5-libs \
        openssl \
        shadow-utils \
        hostname \
        curl \
        tzdata \
        diffutils \
        libaio \
        which \
        pam \
        procps-ng \
        cracklib-dicts \
        tar; \
    microdnf update -y libksba; \
    microdnf clean all; \
    rm -rf /var/cache/dnf /var/cache/yum

# create mysql user/group before mysql installation
RUN groupadd -g 1001 mysql; \
    useradd -u 1001 -r -g 1001 -s /sbin/nologin \
        -c "Default Application User" mysql

# we need licenses from docs
RUN set -ex; \
    # systemd is required for nss-pam-ldap
    curl -Lf -o /tmp/nss-pam-ldapd.rpm http://vault.centos.org/centos/8/AppStream/x86_64/os/Packages/nss-pam-ldapd-0.9.9-3.el8.x86_64.rpm; \
    rpmkeys --checksig /tmp/nss-pam-ldapd.rpm; \
    rpm -iv /tmp/nss-pam-ldapd.rpm --nodeps; \
    rm -rf /tmp/nss-pam-ldapd.rpm; \
    curl -Lf -o /tmp/percona-xtradb-cluster-server.rpm https://repo.percona.com/pxc-80/yum/${PXC_REPO}/8/RPMS/x86_64/percona-xtradb-cluster-server-${FULL_PERCONA_XTRADBCLUSTER_VERSION}.x86_64.rpm; \
    curl -Lf -o /tmp/percona-xtradb-cluster-shared.rpm https://repo.percona.com/pxc-80/yum/${PXC_REPO}/8/RPMS/x86_64/percona-xtradb-cluster-shared-${FULL_PERCONA_XTRADBCLUSTER_VERSION}.x86_64.rpm; \
    curl -Lf -o /tmp/percona-xtradb-cluster-client.rpm https://repo.percona.com/pxc-80/yum/${PXC_REPO}/8/RPMS/x86_64/percona-xtradb-cluster-client-${FULL_PERCONA_XTRADBCLUSTER_VERSION}.x86_64.rpm; \
    curl -Lf -o /tmp/percona-xtradb-cluster-shared-compat.rpm https://repo.percona.com/pxc-80/yum/${PXC_REPO}/8/RPMS/x86_64/percona-xtradb-cluster-shared-compat-${FULL_PERCONA_XTRADBCLUSTER_VERSION}.x86_64.rpm; \
    curl -Lf -o /tmp/percona-xtradb-cluster-icu-data-files.rpm https://repo.percona.com/pxc-80/yum/${PXC_REPO}/8/RPMS/x86_64/percona-xtradb-cluster-icu-data-files-${FULL_PERCONA_XTRADBCLUSTER_VERSION}.x86_64.rpm; \
    rpmkeys --checksig /tmp/percona-xtradb-cluster-shared-compat.rpm /tmp/percona-xtradb-cluster-server.rpm /tmp/percona-xtradb-cluster-shared.rpm /tmp/percona-xtradb-cluster-client.rpm; \
    rpm -iv /tmp/percona-xtradb-cluster-shared-compat.rpm /tmp/percona-xtradb-cluster-server.rpm /tmp/percona-xtradb-cluster-shared.rpm /tmp/percona-xtradb-cluster-client.rpm /tmp/percona-xtradb-cluster-icu-data-files.rpm --nodeps; \
    microdnf clean all; \
    rm -rf /tmp/percona-xtradb-cluster-shared-compat.rpm /tmp/percona-xtradb-cluster-server.rpm /tmp/percona-xtradb-cluster-shared.rpm /tmp/percona-xtradb-cluster-client.rpm /tmp/percona-xtradb-cluster-icu-data-files.rpm; \
    rm -rf /usr/bin/mysqltest /usr/bin/perror /usr/bin/replace /usr/bin/resolve_stack_dump /usr/bin/resolveip; \
    rm -rf /var/cache/dnf /var/cache/yum /var/lib/mysql /usr/lib64/mysql/plugin/debug /usr/sbin/mysqld-debug /usr/lib64/mecab /usr/lib64/mysql/mecab /usr/bin/myisam*; \
    rpm -ql percona-xtradb-cluster-client | egrep -v "mysql$|mysqldump$|mysqladmin$|mysqlbinlog$" | xargs rm -rf

COPY LICENSE /licenses/LICENSE.Dockerfile
RUN cp /usr/share/doc/percona-xtradb-cluster-galera/COPYING /licenses/LICENSE.galera; \
    cp /usr/share/doc/percona-xtradb-cluster-galera/LICENSE.* /licenses/

COPY dockerdir /
COPY --from=go_builder /go/src/github.com/percona/percona-xtradb-cluster-operator/src/peer-list /usr/bin/

RUN set -ex; \
    rmdir /etc/my.cnf.d; \
    ln -s /etc/mysql/conf.d /etc/my.cnf.d; \
    rm -f /etc/percona-xtradb-cluster.conf.d/*.cnf; \
    echo '!include /etc/mysql/node.cnf' > /etc/my.cnf; \
    echo '!includedir /etc/my.cnf.d/' >> /etc/my.cnf; \
    echo '!includedir /etc/percona-xtradb-cluster.conf.d/' >> /etc/my.cnf

RUN set -ex; \
    mkdir -p /etc/mysql/conf.d/ /var/log/mysql /var/lib/mysql /docker-entrypoint-initdb.d /etc/percona-xtradb-cluster.conf.d; \
    chown -R 1001:1001 /etc/mysql/ /var/log/mysql /var/lib/mysql /docker-entrypoint-initdb.d /etc/percona-xtradb-cluster.conf.d; \
    chmod -R g=u /etc/mysql/ /var/log/mysql /var/lib/mysql /docker-entrypoint-initdb.d /etc/percona-xtradb-cluster.conf.d

ARG DEBUG
RUN if [[ -n $DEBUG ]] ; then \
    set -ex; \
    sed -i '/\[mysqld\]/a wsrep_log_conflicts\nlog_error_verbosity=3\nwsrep_debug=1' /etc/mysql/node.cnf; \
    mv /usr/sbin/mysqld /usr/sbin/mysqld-ps; \
    cp /usr/local/bin/mysqld-debug /usr/sbin/mysqld; \
    percona-release enable pdpxc-${PXC_VERSION%-*} ${PXC_REPO}; \
    microdnf install -y \
        net-tools \
        nc \
        percona-toolkit \
        gdb; \
    percona-release disable pdpxc-${PXC_VERSION%-*} ${PXC_REPO}; \
    curl -Lf -o /tmp/telnet.rpm http://vault.centos.org/centos/8/AppStream/x86_64/os/Packages/telnet-0.17-76.el8.x86_64.rpm; \
    curl -Lf -o /tmp/tcpdump.rpm http://vault.centos.org/centos/8/AppStream/x86_64/os/Packages/tcpdump-4.9.3-2.el8.x86_64.rpm; \
    curl -Lf -o /tmp/perf.rpm https://yum.oracle.com/repo/OracleLinux/OL8/baseos/latest/x86_64/getPackage/perf-4.18.0-477.13.1.el8_8.x86_64.rpm; \
    curl -Lf -o /tmp/strace.rpm http://vault.centos.org/centos/8/BaseOS/x86_64/os/Packages/strace-5.7-3.el8.x86_64.rpm; \
    curl -Lf -o /tmp/percona-xtradb-cluster-debuginfo.rpm https://repo.percona.com/pxc-80/yum/${PXC_REPO}/8/RPMS/x86_64/percona-xtradb-cluster-debuginfo-${FULL_PERCONA_XTRADBCLUSTER_VERSION}.x86_64.rpm; \
    curl -Lf -o /tmp/percona-xtradb-cluster-server-debuginfo.rpm https://repo.percona.com/pxc-80/yum/${PXC_REPO}/8/RPMS/x86_64/percona-xtradb-cluster-server-debuginfo-${FULL_PERCONA_XTRADBCLUSTER_VERSION}.x86_64.rpm; \
    rpmkeys --checksig /tmp/telnet.rpm /tmp/tcpdump.rpm /tmp/perf.rpm /tmp/strace.rpm /tmp/percona-xtradb-cluster-debuginfo.rpm /tmp/percona-xtradb-cluster-server-debuginfo.rpm; \
    rpm -i /tmp/telnet.rpm /tmp/tcpdump.rpm /tmp/perf.rpm /tmp/strace.rpm /tmp/percona-xtradb-cluster-debuginfo.rpm /tmp/percona-xtradb-cluster-server-debuginfo.rpm --nodeps; \
    rm -rf /tmp/telnet.rpm /tmp/tcpdump.rpm /tmp/perf.rpm /tmp/strace.rpm /tmp/percona-xtradb-cluster-debuginfo.rpm /tmp/percona-xtradb-cluster-server-debuginfo.rpm; \
    microdnf clean all; \
    rm -rf /var/cache/dnf /var/cache/yum; \
fi

USER 1001

VOLUME ["/var/lib/mysql", "/var/log/mysql"]

ENTRYPOINT ["/entrypoint.sh"]

EXPOSE 3306 4567 4568 33060
CMD ["mysqld"]
