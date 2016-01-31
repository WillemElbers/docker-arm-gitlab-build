# Reference:
#   https://gitlab.com/gitlab-org/gitlab-ce/blob/master/doc/install/installation.md

FROM test/gitlab-base:1.0.0

# Create a git user for GitLab
RUN adduser --disabled-login --gecos 'GitLab' git

RUN cd /home/git \
 && sudo -u git -H git clone https://gitlab.com/gitlab-org/gitlab-ce.git -b 8-4-stable gitlab

RUN cd /home/git/gitlab \
 && sudo -u git -H cp config/secrets.yml.example config/secrets.yml \
 && sudo -u git -H chmod 0600 config/secrets.yml \
 # Make sure GitLab can write to the log/ and tmp/ directories
 && sudo chown -R git log/ \
 && sudo chown -R git tmp/ \
 && sudo chmod -R u+rwX,go-w log/ \
 && sudo chmod -R u+rwX tmp/ \
 # Make sure GitLab can write to the tmp/pids/ and tmp/sockets/ directories
 && sudo chmod -R u+rwX tmp/pids/ \
 && sudo chmod -R u+rwX tmp/sockets/ \
 # Make sure GitLab can write to the public/uploads/ directory
 && mkdir -p public/uploads \
 && sudo chmod -R u+rwX  public/uploads \
 # Change the permissions of the directory where CI build traces are stored
 && sudo chmod -R u+rwX builds/ \
 # Change the permissions of the directory where CI artifacts are stored
 && sudo chmod -R u+rwX shared/artifacts/ \
 # Configure Git global settings for git user, used when editing via web editor
 && sudo -u git -H git config --global core.autocrlf input

# Copy over the configuration
COPY assets/config /home/git/gitlab/config

# Reduce permission for database configuration
RUN chown -R git /home/git/gitlab \
 && sudo -u git -H chmod o-rwx /home/git/gitlab/config/database.yml

#Install gitlab
RUN cd /home/git/gitlab \
 && sudo -u git -H bundle install --deployment --without development test mysql aws kerberos

#Install gitlab-shell
RUN cd /home/git/gitlab \
 && sudo -u git -H bundle exec rake gitlab:shell:install REDIS_URL=redis://172.17.42.1:6379 RAILS_ENV=production

#Install gitlab workhorse
RUN ln -s /usr/local/go/bin/go /usr/bin/go \
 && cd /home/git \
 && sudo -u git -H git clone https://gitlab.com/gitlab-org/gitlab-workhorse.git \
 && cd gitlab-workhorse \
 && sudo -u git -H git checkout 0.5.4 \
 && sudo -u git -H make

RUN cd /home/git/gitlab \
 && echo "yes" | sudo -u git -H bundle exec rake gitlab:setup RAILS_ENV=production

RUN cd /home/git/gitlab \
 && sudo -u git -H bundle exec rake gitlab:env:info RAILS_ENV=production \
 && sudo -u git -H bundle exec rake assets:precompile RAILS_ENV=production

RUN cp /home/git/gitlab/lib/support/init.d/gitlab /etc/init.d/gitlab

#Fix permissions
RUN sudo chmod -R ug+rwX,o-rwx /home/git/repositories/ \
 && sudo chmod -R ug-s /home/git/repositories/ \
 && sudo find /home/git/repositories/ -type d -print0 | sudo xargs -0 chmod g+s \
 && sudo chmod 0750 /home/git/gitlab/public/uploads

WORKDIR /home/git/gitlab

ENV RAILS_ENV="production"

RUN apt-get update \
 && apt-get install -y supervisor
#RAILS_ENV=$RAILS_ENV bin/web start
#RAILS_ENV=$RAILS_ENV bin/background_jobs start &
#$app_root/bin/daemon_with_pidfile $gitlab_workhorse_pid_path  \
#      /usr/bin/env PATH=$gitlab_workhorse_dir:$PATH \
#        gitlab-workhorse $gitlab_workhorse_options \
#      >> $gitlab_workhorse_log 2>&1 &
#RAILS_ENV=$RAILS_ENV bin/mail_room start &

COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf
COPY supervisor/gitlab.conf /etc/supervisor/conf.d/gitlab.conf
COPY supervisor/gitlab_workhorse.conf /etc/supervisor/conf.d/gitlab_workhorse.conf
#COPY supervisor/sidekiq.conf /etc/supervisor/conf.d/sidekiq.conf

COPY redis-cli /usr/local/bin/redis-cli
RUN chmod u+x /usr/local/bin/redis-cli \
 && chmod -R go-w /go

COPY gitlab-shell/config.yml /home/git/gitlab-shell/config.yml
#COPY gitlab-shell/gitlab_config.rb /home/git/gitlab-shell/lib/gitlab_config.rb

EXPOSE 8080

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]
