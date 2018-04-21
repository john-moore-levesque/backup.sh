#!/bin/bash
###############################################################################
# backup.sh - created by John Moore-Levesque, 4/20/218
# Usage:
#   sh backup.sh [@drush-alias]
###############################################################################

###############################################################################
# Variables
###############################################################################
BACKUPROOT="/usr/local/backups"
LOGFILEDIR="/usr/local/logs/backups"
DRUSHDIR="/usr/bin"
DIRDATE=`date '+%Y%m%d%H%M'`
KEEP_DAILY_X_DAYS=7
KEEP_WEEKLY_X_DAYS=31
KEEP_YEARLY_X_DAYS=369
umask 077

###############################################################################
# Verify Environment
###############################################################################
# Make sure drush is present
if [ ! -f "${DRUSHDIR}/drush" ]
then
	echo "No drush found; exiting."
	exit
fi

# Confirm LOGFILEDIR exists
if [ ! -d "${LOGFILEDIR}" ]
then
	# make LOGFILEDIR if it doesn't exist
	mkdir -p ${LOGFILEDIR}

	# Exit if LOGFILEDIR not writable
	if [ $? -ne 0 ]
	then
		echo "ERROR! Couldn't create ${LOGFILEDIR}."
		exit
	fi
fi

# Create the backup log if it doesn't already exist
if [ ! -f "${LOGFILEDIR}/backup.log" ]
then
	touch ${LOGFILEDIR}/backup.log
fi

echo "Output will be in ${LOGFILEDIR}/backup.log" | tee -a ${LOGFILEDIR}/backup.log

# Confirm backup root exists
if [ ! -d "${BACKUPROOT}" ]
then
	# Create BACKUPROOT if it doesn't exist
	mkdir -p ${BACKUPROOT}

	# Exit if directory path not writable
	if [ $? -ne 0 ]
	then
		echo "ERROR! Couldn't create ${BACKUPROOT}." | tee -a ${LOGFILEDIR}/backup.log
		exit
	fi
fi

# Confirm drush alias	
if [ "${1}" ]
then
	DRUSH_ENV=`echo "${1}" | sed -e 's/^ *//' -e 's/ *$//' | cut -c2-`
	ALIASCHECKDIR=`${DRUSHDIR}/drush st | grep "Drush alias files" | cut -f2 -d: | tr -d [:space:]`
	ALIASCHECK=`grep '^$aliases' ${ALIASCHECKDIR} | grep \'${DRUSH_ENV}\' | cut -f2 -d\'`
	if [ "${DRUSH_ENV}" == "${ALIASCHECK}" ]
	then
		DRUSHOPT="${1}"
		WEBROOT=`${DRUSHDIR}/drush ${DRUSHOPT} st | grep "Drupal root" | cut -f2 -d: | tr -d [:space:]`
		BACKUPDIR="${BACKUPROOT}/${DRUSH_ENV}"
		
		# Make sure BACKUPROOT/DRUSH_ENV exists
		if [ ! -d ${BACKUPDIR} ]
		then
			mkdir -p ${BACKUPDIR}
			
			# Exit if directory path not writable
			if [ $? -ne 0 ]
			then
				echo "ERROR! Couldn't create ${BACKUPDIR}." | tee -a ${LOGFILEDIR}/backup.log
				exit
			fi
		fi

	else
		echo "You must enter a valid drush environment - valid options are: ${ALIASCHECK}" | tee -a ${LOGFILEDIR}/backup.log
		exit
	fi
else
	echo "You must provide a drush alias (including the @ sign); exiting." | tee -a ${LOGFILEDIR}/backup.log
	exit
fi

###############################################################################
# Main
###############################################################################
echo "/-------------------/" >> ${LOGFILEDIR}/backup.log
echo "backup.sh started at `date`" >> ${LOGFILEDIR}/backup.log
echo "backups placed in ${BACKUPDIR}" >> ${LOGFILEDIR}/backup.log

# Put the site in maintenance mode
${DRUSHDIR}/drush ${DRUSHOPT} sset --yes system.maintenance_mode 1
echo "Site now in maintenance mode" >> ${LOGFILEDIR}/backup.log

# Clear the caches
${DRUSHDIR}/drush ${DRUSHOPT} cache-rebuild
echo "cache cleared" >> ${LOGFILEDIR}/backup.log

# Create a tarball of the webroot
cd ${WEBROOT}
tar -czvf ${BACKUPDIR}/dailyfiles${DIRDATE}.tar.gz .???* * >> ${LOGFILEDIR}/backup.log

# Create a database dump and gzip the result
${DRUSHDIR}/drush ${DRUSHOPT} sql-dump --result-file=${BACKUPDIR}/dailymysqldump${DIRDATE}.sql --gzip

echo "Backup finished at `date`" >> ${LOGFILEDIR}/backup.log

# Take the site out of maintenance mode
${DRUSHDIR}/drush ${DRUSHOPT} sset --yes system.maintenance_mode 0
echo "Site out of maintenance mode" >> ${LOGFILEDIR}/backup.log

# Clear the caches
${DRUSHDIR}/drush ${DRUSHOPT} cache-rebuild
echo "cache cleared" >> ${LOGFILEDIR}/backup.log

echo "" >> ${LOGFILEDIR}/backup.log

###############################################################################
# Clean up backup directory
###############################################################################
cd ${BACKUPDIR}

echo "Starting cleanup at `date`" >> ${LOGFILEDIR}/backup.log
if [ `date +%d` -eq 01 ]
then
	mv dailyfiles${DIRDATE}.tar.gz monthlyfiles${DIRDATE}.tar.gz
	mv dailymysqldump${DIRDATE}.sql.gz monthlysql${DIRDATE}.sql.gz
elif [ `date +%w` -eq 0 ]
then
	mv dailyfiles${DIRDATE}.tar.gz weeklyfiles${DIRDATE}.tar.gz
	mv dailymysqldump${DIRDATE}.sql.gz dailymysqldump${DIRDATE}.sql.gz
fi

for FILE in `find ${BACKUPDIR} -name "daily*" -ctime ${KEEP_DAILY_X_DAYS}`
do
	echo "Removing ${FILE} since it is older than ${KEEP_DAILY_X_DAYS}." >> ${LOGFILEDIR}/backup.log
	rm ${FILE}
done

for FILE in `find ${BACKUPDIR} -name "weekly*" -ctime ${KEEP_WEEKLY_X_DAYS}`
do
	echo "Removing ${FILE} since it is older than ${KEEP_WEEKLY_X_DAYS}." >> ${LOGFILEDIR}/backup.log
	rm ${FILE}
done

for FILE in `find ${BACKUPDIR} -name "monthly*" -ctime ${KEEP_MONTHLY_X_DAYS}`
do
	echo "Removing ${FILE} since it is older than ${KEEP_MONTHLY_X_DAYS}." >> ${LOGFILEDIR}/backup.log
	rm ${FILE}
done

echo "Cleanup finished at `date`" >> ${LOGFILEDIR}/backup.log
echo "" > ${LOGFILEDIR}/backup.log
