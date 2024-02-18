# Sigh, debian
SHELL=/bin/bash
BOOT=/boot/firmware

halp: /usr/bin/nc /usr/sbin/ntpd
	@echo 'Run "make setup" to configure this device.'
	@echo 'Current config:'
	@echo "  * CPU Speed $$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq) Hz (Should be 1000000)"
	@echo "  * CPU Governor: $$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor) (Should be 'performance')"
	@if grep -q 'nohz=off' /proc/cmdline; then \
		echo "  * nohz=off present on kernel command line"; \
	else \
		echo "  * nohz=off IS NOT PRESENT on kernel boot command line"; \
	fi
	@if grep -q 'elevator=deadline' /proc/cmdline; then \
		echo "  * elevator=deadline present on kernel command line"; \
	else \
		echo "  * elevator=deadline IS NOT PRESENT on kernel boot command line"; \
	fi
	@if [ ! -e $(BOOT)/config.txt ]; then \
		echo "  * $(BOOT)/config.txt does not exist, can't check config"; \
	else \
		PPSDT=$$(grep ^dtoverlay=pps-gpio $(BOOT)/config.txt); \
		if [ ! "$$PPSDT" ]; then \
			echo "  * pps-gpio overlay not enabled in $(BOOT)/config.txt"; \
		else \
			echo "  * pps-gpio dtoverlay present as '$$PPSDT'"; \
		fi \
	fi; \
	DEVJSON=$$(echo '?DEVICES;' | nc -N localhost 2947 | grep DEVICES); \
	if [ ! "$$DEVJSON" ]; then \
		echo "Could not connect to gpsd, no device information"; \
	else \
		echo "  * gpsd reports $$(echo $$DEVJSON | jq '.devices | length') devices (should be 1)"; \
		TYPE=$$(echo $$DEVJSON | jq -r '.devices[0].driver'); \
		echo "  * gpsd Device 1 is '$$TYPE'"; \
		if [ "$$TYPE" == "u-blox" ]; then \
			echo -e "\n**** This is a u-blox device, and can be configured for higher precision ****"; \
			echo -e "**** run 'make ublox' for more information ****\n"; \
		fi; \
	fi; \
	echo "NTP Stats (from ntpq -crv -pn)"; \
	ntpq -crv -pn


.PHONY: ublox
ublox:
	@echo "All u-blox devices can be set to 'Stationary' mode, which makes them"
	@echo "more accurate (when stationary!). You can configure this with the"
	@echo "following commands:"
	@echo "# Reset the u-blox to factory defaults"
	@echo "ubxtool -p RESET"
	@echo "# Set the Dynamic Platform Model to 1 (Stationary)"
	@echo "ubxtool -p MODEL,1"
	@echo "# Save to RAM, Battery Backup, and Flash"
	@echo "ubxtool -p SAVE,0"
	@echo "ubxtool -p SAVE,1"
	@echo "ubxtool -p SAVE,2"
	@echo "ubxtool -p SAVE,3"
	@echo -e "\nAfter making these changes, POWER CYCLE this device, and the"
	@echo "GPS receiver, to make sure the changes persist."
	@echo -e "\nYou can get the CURRENT Dynamic model with the following command:"
	@echo "ubxtool -p CFG-NAV5 | grep dynMod"
	@echo "Full protocol PDF can be downloaded from https://bit.ly/ublox6"


.PHONY: setup
setup: packages udev gpsd ntpsec /etc/hosts $(BOOT)/cmdline.txt $(BOOT)/config.txt
       
.PHONY: packages
packages: /usr/bin/ansible-playbook /usr/bin/wg /usr/bin/ppscheck /usr/sbin/ntpd /usr/bin/vim /usr/bin/host

.PHONY: wireguard
wireguard: /etc/wireguard/wg0.conf

.PHONY: hostname
hostname: /etc/hosts

.PHONY: udev
udev: /etc/udev/rules.d/09.pps.rules

.PHONY: gpsd
gpsd: /usr/sbin/gpsd /etc/default/gpsd

.PHONY: ntpsec ntp
ntp ntpsec: /etc/ntpsec/ntp.conf /var/log/ntpsec /etc/default/ntpsec

/var/log/ntpsec:
	@mkdir $@ && chown ntpsec:ntpsec $@

/etc/default/ntpsec: ntpsec.default
	cp $< $@

/etc/ntpsec/ntp.conf: ntp.conf
	cp $< $@
	systemctl restart ntpsec

POOL=2.$(shell cat .conf.region).pool.ntp.org
ntp.conf: .conf.region conf/ntp.conf
	@echo -e "\nChecking $(POOL)"
	@host $(POOL) || ( rm -f .conf.region; exit 1)
	@sed 's/__POOL__/$(POOL)/' < conf/ntp.conf > $@

ntp-reconf: region-reconf /etc/ntp.conf

.PHONY: region-reconf
region-reconf .conf.region:
	@read -n3 -p "Enter your two letter country code [AU] " rconf && if [ "$$rconf" ]; then \
	       	echo $$rconf > .conf.region ; \
	else \
		echo AU > .conf.region; \
	fi

/etc/default/gpsd: defaults.gpsd
	cp $< $@

/etc/udev/rules.d/09.pps.rules: pps.rules
	cp $< $@

.PHONY: ansible
ansible /etc/hosts: /etc/ansible.hostname
	cd ansible && ansible-playbook localhost.yml -e hostname=$(shell cat /etc/ansible.hostname)

# elevator=deadline is for disk IO only, and isn't important, but it can help when
# you're using slow SD cards.
$(BOOT)/cmdline.txt: $(BOOT)/cmdline.fix
	@sed -r -e 's/console=ser[^ ]+ //' -e 's/rootwait quiet/rootwait nohz=off elevator=deadline smsc95xx.turbo_mode=N quiet/' < $< > $@

$(BOOT)/cmdline.fix:
	@cp $(BOOT)/cmdline.txt $@

$(BOOT)/config.txt: $(BOOT)/config.orig
	@if ! grep -q "RPI NTP" $(BOOT)/config.txt; then \
		cat config.append.txt >> $(BOOT)/config.txt; \
		systemctl disable hciuart.service; \
		sed -i 's/^arm_boost=1/arm_boost=0/' $(BOOT)/config.txt; \
	fi
		
$(BOOT)/config.orig:
	@cp $(BOOT)/config.txt $@


.PHONY: force-hostname
force-hostname /etc/ansible.hostname:
	@C=$(shell hostname); echo "Current hostname '$$C'"; read -p "Set hostname (blank to not change): " h; \
	if [ "$$h" ]; then \
		echo $$h > /etc/ansible.hostname; \
	else \
		if [ ! -s /etc/ansible.hostname ]; then \
			hostname > /etc/ansible.hostname; \
		fi; \
	fi

/etc/wireguard/wg0.conf: /etc/wireguard/public.key
	#@read -p 'What is your IP address? ' ip
	@echo "Yeah nah" && exit 1

/etc/wireguard/private.key:
	 (umask 0077; wg genkey > $@)

/etc/wireguard/public.key: /etc/wireguard/private.key
	wg pubkey < $< > $@

/usr/bin/ansible-playbook /usr/bin/wg /usr/bin/ppscheck /usr/bin/vim:
	apt-get -y install ansible wireguard pps-tools vim

/usr/sbin/gpsd:
	apt-get -y install gpsd gpsd-tools gpsd-clients

/usr/sbin/ntpd:
	apt-get -y install ntpsec ntpstat

/usr/bin/nc:
	apt-get -y install netcat-openbsd

/usr/bin/host:
	apt-get -y install bind9-host
