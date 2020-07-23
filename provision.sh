#!/usr/bin/env bash

# Include utilities.
source provisioning-utils.sh

log_step "Starting provisioning process..."

# TODO put this back.
## log_step "Bringing down any existing containers..."
## docker-compose down

# TODO put this back.
## log_step "Pulling latest images..."
## docker-compose pull --include-deps app

log_step "Bringing up containers..."
docker-compose up --detach app

log_step "Waiting until we can run a MySQL query..."
until docker-compose exec -T mysql mysql -u root -se "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'root')" &> /dev/null
do
  printf "."
  sleep 1
done

log_step "Waiting a few seconds to make sure MySQL is ready..."
sleep 5

# Ensure that the MySQL databases and users are created for dependencies
# (A no-op for databases and users that already exist).
log_step "Ensuring MySQL databases and users exist..."
docker-compose exec -T mysql bash -c "mysql -uroot mysql" < provision.sql

for dependency in lms discovery ; do
	log_message "Provisioning dependency: ${dependency}..."
	if ! ./provision-"$dependency".sh ; then
		log_error "Error occured while provisioning ${dependency}; stopping."
		exit 1
	fi
done

log_message "Provisioning app..."

log_step "app: Running migrations..."
service_exec app make migrate

log_step "app: Creating superuser..."
service_create_edx_user app

log_step "app: Creating users and API applications for integrating with LMS..."
create_lms_integration_for_service enterprise_catalog 18160

# TODO: Handle https://github.com/edx/enterprise-catalog/blob/master/docs/getting_started.rst#permissions

# TODO: Do we still need this?
# If so, the username should be enterprise_catalog_worker, not enterprise_worker.
## log_step "Granting enterprise_worker user in permissions..."
## service_exec_python lms "\
## from django.contrib.auth import get_user_model; \
## from django.contrib.auth.models import Permission; \
## User = get_user_model(); \
## enterprise_worker = User.objects.get(username='enterprise_worker'); \
## enterprise_model_permissions = list(Permission.objects.filter(content_type__app_label='enterprise')); \
## enterprise_worker.user_permissions.add(*enterprise_model_permissions); \
## enterprise_worker.save(); \
## "

log_step "Restarting all containers..."
docker-compose restart

log_step "Provision complete!"