!
! This is a bootblock to load an execute a standalone program from an
! MSDOS filesystem on a floppy disk.
!
! The file loaded is called 'BOOTFILE.SYS' it can be changed at install time
! by following the label boot_name.
!
! The file is loaded at address $7C00, this means it can be the image of a 
! boot block (eg LILO). It's also checked for the magic number associated
! with a Linux-8086 standalone executable and this is used if found.
!
! There are a number of assumptions made by the code concerning the layout
! of the msdos files system:
!
! 1) All of the first FAT must be on the first track.
! 2) The FAT must be 12 bit
! 3) The value of the hidden sectors field must be zero
! 4) There must be two heads on the disk.
!
! All these are true for mtools created floppies on normal PC drives.
!
ORGADDR=$0500

use16

! Some configuration values
LOADSEG=	$7C0

!-------------------------------------------------------------------------
! Absolute position macro, fails if code before it is too big.
macro locn
  if *-start>?1
   fail! *-start>?1
  endif
  .blkb	?1 + start-*
mend

heads=2			! This can be 1 or 2 ONLY. (1 is untested)

org ORGADDR
start:
include sysboot.s

! Data into the temp area, 30 clear bytes
org floppy_temp
root_count:	.blkw	1
old_bpb:	.blkw	2
bios_disk:	.blkb	12

  locn(codestart-start)

  cld			! Assume _nothing_!
  mov	bx,#$7C00	! Pointer to start of BB.
  xor	ax,ax		! Segs all to zero
  mov	ds,ax
  mov	es,ax
  mov	ss,ax
  mov	sp,bx		! SP Just below BB
  mov	cx,#$100	! Move 256 words
  mov	si,bx		! From default BB
  mov	di,#ORGADDR	! To the correct address.
  rep
   movsw
  jmpi	cont,#0		! Set CS:IP correct.
cont:
  sti			! Let the interrupts back in.

! Need to fix BPB for fd0 to correct sectors (Like linux bootblock does)
  mov	di,#bios_disk
  mov	bp,#0x78		
! 0:bx is parameter table address
  push	ds
  lds	si,[bp]

! ds:si is source

  mov	cx,#6			
! copy 12 bytes
  push	di
  rep
   movsw
  pop	di
  pop	ds

! New BPB is 0:di
  mov	[bp],di
  mov	2[bp],ax

  mov	al,[dos_spt]	! Finally, correct spt.
  mov	4[di],al

! For each sector in root dir
! For each dir entry
! If entry name is == boot_name
! then load and run

  ! First dir = dos_fatlen*dos_nfat+dos_resv
  mov	ax,[dos_fatlen]
  mov	dl,[dos_nfat]
  xor	dh,dh
  mul	dx
  add	ax,[dos_resv]
  ! Assume: dos_hidden == 0
  mov	di,ax
  ! DI is sector number of first root dir sector.

  mov	ax,[dos_nroot]
  mov	[root_count],ax
  add	ax,#15
  mov	cl,#4
  shr	ax,cl
  add	ax,di
  mov	bp,ax		! bp is first data sector.

nextsect:
  call	linsect
  mov	ax,#$0201
  int	$13
  jc	floppy_error

! ... foreach dir entry
  mov	si,bx
nextentry:

  ! Test attributes for !dir !label here ?

! test entry name
  push	si
  push	di
  mov	di,#boot_name
  mov	cx,#11
  rep
   cmpsb
  pop	di
  pop	si
  jne	bad_entry

  mov	ax,[si+26]	! Cluster number of start of file
  test	ax,ax		! Make sure we have a block.
  jnz	load_system

bad_entry:
  add	si,#32		! skip to next entry
  cmp	si,#512
  jnz	nextentry

  inc	di		! Load next sector
  sub	[root_count],#16
  jp	nextsect
  jmp	no_system

! Convert a cluster number in AX into a CHS in CX:DX
linclust:
  sub	ax,#2
  mov	dl,[dos_clust]
  xor	dh,dh
  mul	dx
  add	ax,bp		! Add sector number of first data sector.
  jmp	linsect2

!
! This function converts a linear sector number in DI 
! into a CHS representation in CX:DX
!
linsect:
  mov	ax,di
linsect2:
  xor	dx,dx
  div	[dos_spt]
  inc	dx
  mov	cl,dl	! Sector num
  xor	dx,dx	! Drive 0
 if heads =2
  shr	ax,#1	! Assume dos_heads == 2
  adc	dh,#0	! Head num
 endif
  mov	ch,al	! Cylinder
  ret

error_msg:
  .asciz "\r\nError during initial boot\r\nPress a key:"

no_system:
floppy_error:

  mov	si,#error_msg
no_boot:		! SI now has pointer to error message
  lodsb
  cmp	al,#0
  jz	EOS
  mov	bx,#7
  mov	ah,#$E		! Can't use $13 cause that's AT+ only!
  int	$10
  jmp	no_boot
EOS:
  xor	ax,ax
  int	$16
  int	$19		! This should be OK as we haven't touched anything.
  jmpi	$0,$FFFF	! Wam! Try or die!

!
! This loads the boot program 1 sector at a time, funny thing is it actually
! loads at exactly the same speed as loading a track at a time, at least on
! my slow old 286/8Mhz. Oh well, we need the space so if you're worried just
! tell superformat to give you an interleave of 2 (-i 2).
!

load_system:
  push	ax		! Save cluster we're loading

! 1) Load FAT
  ! This assumes all of FAT1 is on the first track, this is normal
  mov	ax,[dos_fatlen]
  mov	ah,#2
  mov	bx,#fat_table
  mov	cx,[dos_resv]	! Fat starts past bootblock
  inc	cx
  xor	dx,dx		! Head zero
  int	$13
  jc	floppy_error

  mov	ax,#LOADSEG
  mov	es,ax
  pop	di		! Cluster to start load.

  ! load whole cluster
next_cluster:

  mov	si,[dos_clust]	! How big is a cluster
  and	si,#255

  mov	ax,di		! Find it's physical address
  call	linclust

next:
  mov	ax,#$0201
  xor	bx,bx
  int	$13		! Load 1 sector at a time
  jc	floppy_error

  mov	ax,es
  add	ax,#512/16
  mov	es,ax

  cmp	cl,[dos_spt]	! Does cluster straddle tracks ?
  jnz	sectok
  mov	cl,#0
 if heads=2
  inc	dh
  cmp	dh,#2		! Does cluster straddle cylinders ?
  jnz	sectok
  xor	dh,dh
 endif
  inc	ch
sectok:
  inc	cl
  dec	si
  jnz	next

  call	next_fat
  jc	next_cluster
  jmp	maincode

next_fat:
  mov	ax,di
  shr	ax,#1
  pushf			! Save if odd number
  add	di,ax
  mov	di,fat_table[di]
  popf
  jnc	noshift		! Odd in high nibbles.
  mov	cl,#4
  shr	di,cl
noshift:
  and	di,#$FFF
  cmp	di,#$FF0	! FFF is EOF, clear carry flag.
  			! FF0+ are badblocks etc.
  ret

maincode:
  mov	bx,#7
  mov	ax,#$0E3E
  int	$10		! Marker printed to say bootblock succeeded.

  xor	dx,dx		! DX=0 => floppy drive
  push	dx		! CX=0 => partition offset = 0

  mov	bx,#LOADSEG
  mov	ds,bx		! DS = loadaddress
  inc	bx
  inc	bx		! bx = initial CS
  xor	di,di		! Zero
  mov	ax,[di]
  cmp	ax,#0x0301	! Right magic ?
  jnz	bad_magic	! Yuk ...
  mov	ax,[di+2]
  and	ax,#$20		! Is it split I/D ?
  jz	impure		! No ...
  mov	cl,#4
  mov	ax,[di+8]
  shr	ax,cl
impure:
  pop	cx		! Partition offset.
  add	ax,bx
  mov	ss,ax
  mov	sp,[di+24]	! Chmem value
  mov	ds,ax

  push	bx		! jmpi	0,#LOADSEG+2
  push	di

  ! AX=ds, BX=cs, CX=X, DX=X, SI=X, DI=0, BP=X, ES=X, DS=*, SS=*, CS=*
  retf
bad_magic:
  jmpi	$7C00,0		! No magics, just go.

export boot_name
boot_name:
 .ascii "BOOTFILESYS"
name_end:
!        NNNNNNNNEEE

locn(512)
fat_table:	! This is the location that the fat table is loaded.
		! Note: The fat must be entirely on track zero.