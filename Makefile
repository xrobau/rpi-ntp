
.PHONY: setup
setup: packages udev gpsd
       
.PHONY: packages
packages: /usr/bin/ansible-playbook /usr/bin/wg /usr/bin/ppscheck

.PHONY: wireguard
wireguard: /etc/wireguard/wg0.conf

.PHONY: hostname
hostname: /etc/hosts

.PHONY: udev
udev: /etc/udev/rules.d/09.pps.rules

.PHONY: gpsd
gpsd: /usr/sbin/gpsd /etc/default/gpsd

/etc/default/gpsd: defaults.gpsd
	cp $< $@

/etc/udev/rules.d/09.pps.rules: pps.rules
	cp $< $@

/etc/hosts: /etc/ansible.hostname
	cd ansible && ansible-playbook localhost.yml -e hostname=$(shell cat /etc/ansible.hostname)

/etc/ansible.hostname:
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

/usr/bin/ansible-playbook /usr/bin/wg /usr/bin/ppscheck:
	apt-get -y install ansible wireguard pps-tools

/usr/sbin/gpsd:
	apt-get -y install gpsd gpsd-tools gpsd-clients

