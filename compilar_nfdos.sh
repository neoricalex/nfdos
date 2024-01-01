#!/usr/bin/env sh

source .env

instalar_requerimentos(){

		echo "==> Instalar pacotes para a criação da imagem ISO..."
		sudo apt install -y \
			binutils \
			debootstrap \
			squashfs-tools \
			xorriso \
			grub-pc-bin \
			grub-efi-amd64-bin \
			mtools \
			whois \
			jq \
			moreutils \
			make \
			unzip

		echo "==> Removendo pacotes do Ubuntu desnecessários"
		sudo apt autoremove -y
		
}

compilar_iso(){

	echo "Iniciando a compilação da imagem ISO do NFDOS $NFDOS_VERSAO ..."

	echo "Checkando se a $NFDOS_ROOT existe"
	if [ ! -d "$NFDOS_ROOT" ]; then
		mkdir -p $NFDOS_HOME/core
		mkdir -p $NFDOS_HOME/desktop
	fi

	echo "Checkando se a $NFDOS_ROOT/nfdos.iso existe"
	if [ ! -f "$NFDOS_ROOT/nfdos.iso" ]; then

		echo "A $NFDOS_ROOT/nfdos.iso não existe."

		echo "Checkando se é necessário limpar alguns vestigios do desenvolvimento"
		if [ -d "$NFDOS_ROOT/image" ]; then
			sudo rm -rf $NFDOS_ROOT/image
		fi
		if [ -d "$NFDOS_ROOT/rootfs" ]; then
			sudo rm -rf $NFDOS_ROOT/rootfs
		fi
		if [ -f "$NFDOS_ROOT/nfdos.img" ]; then
			sudo rm -rf $NFDOS_ROOT/nfdos.img
		fi	

		echo "Criando a $NFDOS_ROOT/nfdos.iso..."	
		bash "$NFDOS_ROOT/criar_iso.sh"
	else
		echo "A $NFDOS_ROOT/nfdos.iso existe"
	fi

}

instalar_requerimentos
compilar_iso
