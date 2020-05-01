FROM centos:7

RUN mkdir /out

# helmfile
ENV HELMFILE_VERSION 0.111.0
RUN curl -LO https://github.com/roboll/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_linux_amd64 && \
  mv helmfile_linux_amd64 /out/helmfile && \
  chmod +x /out/helmfile

# kubectl
ENV KUBECTL_VERSION 1.16.0
RUN curl -LO  https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl && \
  mv kubectl /out/kubectl && \
  chmod +x /out/kubectl

# helm 3
# need to build from master until 3.2.1 is fixed so that helm can deploy over failed releases https://github.com/helm/helm/pull/7653#issuecomment-620209072
# ENV HELM3_VERSION 3.2.0
# RUN curl -f -L https://get.helm.sh/helm-v${HELM3_VERSION}-linux-386.tar.gz | tar xzv && \
#   mv linux-386/helm /out/

# git
ENV GIT_VERSION 2.21.1
RUN yum install -y curl-devel expat-devel gettext-devel openssl-devel zlib-devel && \
    yum install -y gcc perl-ExtUtils-MakeMaker make
RUN cd /usr/src  && \
    curl -LO https://www.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.gz  && \
    tar xzf git-${GIT_VERSION}.tar.gz  && \
    cd git-${GIT_VERSION} && \
    make prefix=/usr/local/git all  && \
    make prefix=/usr/local/git install

# Downloading gcloud package
RUN curl https://dl.google.com/dl/cloudsdk/release/google-cloud-sdk.tar.gz > /tmp/google-cloud-sdk.tar.gz

# Installing the package
RUN mkdir -p /usr/local/gcloud \
  && tar -C /usr/local/gcloud -xvf /tmp/google-cloud-sdk.tar.gz \
  && /usr/local/gcloud/google-cloud-sdk/install.sh && \
  /usr/local/gcloud/google-cloud-sdk/bin/gcloud components install beta && \
  /usr/local/gcloud/google-cloud-sdk/bin/gcloud components update

FROM golang:1.12.17

RUN mkdir /out
RUN mkdir -p /go/src/github.com/jenkins-x

WORKDIR /go/src/github.com/jenkins-x

RUN git clone https://github.com/jenkins-x/bdd-jx.git && \
  cd bdd-jx && \
  make testbin && \
  mv build/bddjx /out/bddjx

# Adding the package path to local
ENV PATH $PATH:/usr/local/gcloud/google-cloud-sdk/bin

FROM golang:1.13

RUN mkdir /out
RUN mkdir -p /go/src/github.com/helm

WORKDIR /go/src/github.com/helm

RUN git clone https://github.com/helm/helm.git && \
  cd helm && \
  make build && \
  mv bin/helm /out/helm

# use a multi stage image so we don't include all the build tools above
FROM centos:7
# need to copy the whole git source else it doesn't clone the helm plugin repos below
COPY --from=0 /usr/local/git /usr/local/git
COPY --from=0 /usr/bin/make /usr/bin/make
COPY --from=0 /out /usr/local/bin
COPY --from=1 /out /usr/local/bin
COPY --from=2 /out /usr/local/bin
COPY --from=0 /usr/local/gcloud /usr/local/gcloud


RUN mkdir -p $HOME/.jx/plugins/bin

COPY helm-annotate/build/helm-annotate $HOME/.jx/plugins/bin/helmfile-0.0.11

ENV PATH /usr/local/bin:/usr/local/git/bin:$PATH:/usr/local/gcloud/google-cloud-sdk/bin

RUN cp /usr/local/bin/helm $HOME/.jx/plugins/bin/helm-3.2.0 && \
    cp /usr/local/bin/helmfile $HOME/.jx/plugins/bin/helmfile-0.111.0 && \
    rm /usr/local/bin/helm /usr/local/bin/helmfile && \
    ln -s $HOME/.jx/plugins/bin/helm-3.2.0 /usr/local/bin/helm && \
    ln -s $HOME/.jx/plugins/bin/helm-annotate-0.0.11 /usr/local/bin/helm-annotate && \
    ln -s $HOME/.jx/plugins/bin/helmfile-0.111.0 /usr/local/bin/helmfile


ENV JX_HELM3 "true"

ENV DIFF_VERSION 3.1.1
RUN helm plugin install https://github.com/databus23/helm-diff --version ${DIFF_VERSION} && \
    helm plugin install https://github.com/aslafy-z/helm-git.git && \
    helm plugin install https://github.com/rawlingsj/helm-gcs

# custom built helm-gcs until this is merged https://github.com/hayorov/helm-gcs/pull/44
COPY helm-gcs /root/.local/share/helm/plugins/helm-gcs/bin/helm-gcs
