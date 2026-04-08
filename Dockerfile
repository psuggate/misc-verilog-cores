FROM ubuntu:22.04 AS fantail
# Steps to run build in Docker container:
#
# - Build container:
#     docker build -t gowin-eda .
#
# - Run container:
#     docker run  -v /home/$USER/dev/misc-verilog-cores:/build/misc-verilog-cores:rw \
#                 -v /etc/passwd:/etc/passwd:ro \
#                 -v /etc/group:/etc/group:ro \
#                 -v /home/$USER/:/home/$USER:rw \
#                 -e USER=$USER --user=$UID:`id -g $USER` \
#                 -w="$PWD" [--rm] -it gowin-eda bash
#
MAINTAINER Patrick Suggate "patrick.suggate@gmail.com"
SHELL ["/bin/bash", "-c"]
ARG DEBIAN_FRONTEND=noninteractive

# Define user, in order to use Git and access credentials
ARG USERNAME=patrick
ARG USER_UID=1000
ARG USER_GID=1000

# Create group and user with correct UID/GID
RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m -s /bin/bash ${USERNAME}

# debian setup
RUN apt-get update -y && apt-get install -y locales gawk build-essential bash \
    git wget libglib2.0.0

# Set the locale
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && locale-gen
ENV LC_ALL en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
RUN dpkg-reconfigure --frontend=noninteractive locales && \
    update-locale LANG=$LANG

#
#  Install the Gowin tools. Requires a gowin download of the education edition
##

#
# Todo:
#  - needs a wget/curl task to fetch this?
#  - fetch outside of Dockerfile?
#  - better handling of GoWin versions?
#  - perhaps use an `ARG`?
#
# RUN wget https://cdn.gowinsemi.com.cn/Gowin_V1.9.11.01_Education_Linux.tar.gz
# RUN tar xvf Gowin_V1.9.11.01_Education_Linux.tar.gz

# ARG GOWIN=Gowin_V1.9.8.11_Education_linux.tar.gz

# Note: `Gowin_V1.9.11.03_Education_Linux.tar.gz` seg-faults!
ARG GOWIN=Gowin_V1.9.11.01_Education_Linux.tar.gz
WORKDIR /opt/gowin
COPY $GOWIN .
RUN tar xvf $GOWIN

# For v1.9.11 and later:
RUN apt-get install -y libgl1 libxcomposite1 libnss3 libasound2 libxrandr2 \
    libxdamage1 libxtst6 libxkbcommon0 libdbus-1-3 libxcb-cursor0 libxcb-xinerama0 \
    libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 libxcb-shape0 \
    libxkbcommon-x11-0 fontconfig libfreetype6 libgl1-mesa-glx libgl1-mesa-dri

ENV QT_DEBUG_PLUGINS 1
ENV QT_QPA_PLATFORM xcb
ENV QT_PLUGIN_PATH /opt/gowin/IDE/plugins
ENV LD_LIBRARY_PATH /opt/gowin/IDE/lib

ENV LD_PRELOAD /usr/lib/x86_64-linux-gnu/libfreetype.so.6
# For Fedora:
# ENV LD_PRELOAD /usr/lib64/libfreetype.so.6

RUN ldconfig

#
#  Now setup build directory
##
WORKDIR /build
RUN chown -R $USERNAME:$USERNAME /build
USER $USERNAME
