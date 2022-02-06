# Sigh, debian
SHELL=/bin/bash

.PHONY: setup
setup: packages udev gpsd ntpsec /etc/hosts /boot/cmdline.txt
       
.PHONY: packages
packages: /usr/bin/ansible-playbook /usr/bin/wg /usr/bin/ppscheck /usr/sbin/ntpd /usr/bin/vim

.PHONY: wireguard
wireguard: /etc/wireguard/wg0.conf

.PHONY: hostname
hostname: /etc/hosts

.PHONY: udev
udev: /etc/udev/rules.d/09.pps.rules

.PHONY: gpsd
gpsd: /usr/sbin/gpsd /etc/default/gpsd

.PHONY: ntpd
ntpd: /etc/ntpsec/ntp.conf

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

/etc/hosts: /etc/ansible.hostname
	cd ansible && ansible-playbook localhost.yml -e hostname=$(shell cat /etc/ansible.hostname)

/boot/cmdline.txt: /boot/cmdline.fix
	@sed -r -e 's/console=ser[^ ]+ //' -e 's/rootwait$/rootwait nohz=off elevator=dealine smsc95xx.turbo_mode=N/' < $< > $@

/boot/cmdline.fix:
	@cp /boot/cmdline.txt $@

/boot/config.txt: /boot/config.orig
	@if ! grep -q "RPI NTP" /boot/config.txt; then \
		cat config.append.txt >> /boot/config.txt; \
		systemctl disable hciuart.service; \
	fi
		
/boot/config.orig:
	@cp /boot/config.txt $@


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

