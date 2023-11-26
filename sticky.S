# mp1.S - missile-command version
# Good luck, and have fun!

.data
	
    # Constants for accessing the fields of a struct missile, 
    # struct missile is defined in rtc.h and mp1.h

	NEXT 	  = 0
	X	  = 4
	Y	  = 8
	VX	  = 12
	VY	  = 16
	DEST_X	  = 20
	DEST_Y	  = 24
	EXPLODED  = 28
	C	  = 32

    # Character to draw for an explosion - '@'

	EXPLOSION = 64
    ERASE = 32 # ASCII for space
    CROSSHAIR = 43 # ASCII for +
	SHIFTBITS = 16
	BASEALIVE = 4294967295
	CROSSX = 40
	CROSSY = 12
	XMOST = 79
	YMOST = 24
	YOFFSET = 160
	ROWOFFSET = 3840
	FIRST = 18
	SECOND = 38
	THRID = 58
    

# Data shared between this file and rtc.c helper functions

# This '.globl' directive makes these symbols visible externally
.globl mp1_missile_list, base_alive, mp1_score

mp1_missile_list:	.long 0x0	# Head of list pointer
base_alive:		.long 0x0	# Array of 3 bytes, plus a padding byte
mp1_score:		.long 0x0	# Player's current score


# Data private to this  file

base_pic:     	    .string "/^^^\\"	# Picture of a live base
dead_base_pic: 	    .string "xxxxx"	# Picture of a dead base
crosshairs_x:		.long 0x0	# X-position of the crosshairs
crosshairs_y:		.long 0x0	# Y-position of the crosshairs
allocate_address:    .long 0x0

.text

# void mp1_poke(void);
# You can use this function to write to video memory.
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX

mp1_poke:
		movl    vmem_base_addr(,1),%edx
		movb    %cl,(%edx,%eax,1)
		ret

#   ----------------- Exported functions ---------------------

# void mp1_rtc_tasklet(unsigned long garbage);
# Performs three tasks:
#	(1) updates the list of missiles (implement this in update_missiles,
#           below, and call it from here).
#	(2) Redraw the bases - they may have been overwritten with missiles
#	(3) Redraw the crosshairs - it may have been overwritten with missiles
# Inputs   : none
# Outputs  : none
# Registers: Standard C calling convention

.globl mp1_rtc_tasklet
mp1_rtc_tasklet:
#######################################
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    pushl %esi
    pushl %edi
    
    call update_missiles # start from walk down the linked list
    call cities_check
	call draw_crosshair
	
    popl %edi
    popl %esi
    popl %ebx
    
    leave
		ret

# int mp1_ioctl(unsigned long arg, unsigned int cmd)
# The dispatch function for the MP1 ioctls - should use the cmd argument
# and a jumptable to execute one of the specific ioctls implemented below.
# Inputs   : unsigned long arg - parameter to the mp1_ioctl_....
#          : unsigned int cmd  - specifies which mp1_ioctl_... function 
#          :                     to execute
# Outputs  : Returns an integer - depends on which ioctl() function is called
# Registers: Standard C calling convention

.globl mp1_ioctl
mp1_ioctl:
    movl 8(%esp), %esi
    cmpl $0, %esi
    jl invalid_cmd
    cmpl $4, %esi
    jg invalid_cmd
    jmp *JUMPTABLE(, %esi, 4)
    ret
    
invalid_cmd:
    movl $-1, %eax        
		ret

JUMPTABLE:
    .long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame
# ----------------- Functions private to this file -------------------

# update_missiles: walk down the linked list, check whether the missile is expploding or not, 
# update the x and y location, and draw it on the screen
##################################################
update_missiles:
	pushl %ebp
	movl %esp, %ebp
	pushl %ebx
	pushl %esi
	pushl %edi

	movl mp1_missile_list, %esi                          # head of missile list saved to %esi 
list_traversal:
	cmpl $0, %esi                                        # walk down the linked list, check if the missiles are all finished
	je link_finished                                      # after processing all missiles, redraw cities
	
	movl X(%esi), %eax                                  # erase the missile first, thus, no need to erase again later 
	shrl $SHIFTBITS, %eax								# y position 
	imull $2, %eax, %eax
	movl Y(%esi), %ecx                                  # x position 
	shrl $SHIFTBITS, %ecx
	imull $YOFFSET, %ecx, %ecx
	addl %ecx, %eax   
	movb $ERASE, %cl									# erase the missile
	pushl %esi
	call mp1_poke
	popl %esi
   
	cmpl $0, EXPLODED(%esi)                              # check if the missile is currently exploding, missile not exploded == 0
	jne call_exploded
	
update_position:
    movl VX(%esi), %ebx 							# ebx holds VX value
    addl X(%esi), %ebx								# add VX to X
	shrl $SHIFTBITS, %ebx
	cmpl $0, %ebx
	jl remove_missile
	shrl $SHIFTBITS, %ebx
	cmpl $XMOST, %ebx
	jg remove_missile

	
    movl VY(%esi), %ebx 							# ebx holds VY value
    addl Y(%esi), %ebx								# add VY to Y
	shrl $SHIFTBITS, %ebx
    cmpl $0, %ebx  									# check if the missile move on or off the screen
	jl remove_missile 								# if below zero, remove the missile 
	shrl $SHIFTBITS, %ebx
	cmpl $YMOST, %ebx								# check if y position is greater then 24
	jg remove_missile
	
	movl VX(%esi), %ebx 							# ebx holds VX value
    addl %ebx, X(%esi)	
	movl VY(%esi), %ebx 							# ebx holds VY value
    addl %ebx, Y(%esi)

    movl X(%esi), %ebx								# check x with destination x 
    shrl $SHIFTBITS, %ebx
    movl DEST_X(%esi), %ecx
    cmpl %ebx, %ecx
	jne draw_missile								# if not equal, draw the missile
    movl Y(%esi), %ebx
    shrl $SHIFTBITS, %ebx
    movl DEST_Y(%esi), %ecx 						# check y with destination y 
    cmpl %ebx, %ecx
    je call_exploded								# if x and y are both equal to desination position, draw exploded
                                                          
 draw_missile:   
    movl X(%esi), %eax                                   # find x position 
    shrl $SHIFTBITS, %eax
    imull $2, %eax, %eax
    movl Y(%esi), %ecx                                  # find y postion 
    shrl $SHIFTBITS, %ecx
    imull $YOFFSET, %ecx, %ecx
    addl %ecx, %eax 
    movb C(%esi), %cl    								# draw the missile 
    call mp1_poke   
next_missile:                                              # next missile
    movl (%esi), %esi
    jmp list_traversal
    
call_exploded:
    movl X(%esi), %eax                                   # find x position 
    shrl $SHIFTBITS, %eax
    imull $2, %eax, %eax
    movl Y(%esi), %ecx                                  # find y postion 
    shrl $SHIFTBITS, %ecx
    imull $YOFFSET, %ecx, %ecx
    addl %ecx, %eax 
	xorb %cl, %cl
    movb $EXPLOSION, %cl    
	pushl %esi
    call mp1_poke 										# draw explosion
	popl %esi

    pushl %esi 
    call missile_explode                               # call missile_exploded function
    popl %esi
check_eax:
	cmpl $0, %eax
    je dec_counter                                      # if eax = 0, decrease explosion counter
	call mp1_notify_user

dec_counter:
    movl EXPLODED(%esi), %ebx #
    subl $1, %ebx
    movl %ebx, EXPLODED(%esi)                           # update the value of EXPLODED        
    cmpl $0, EXPLODED(%esi)                             # check exploded = 0 ? again
	je erase_exploded
    jmp next_missile
	
erase_exploded:
    movl X(%esi), %eax                                   # find x position 
    shrl $SHIFTBITS, %eax
    imull $2, %eax, %eax
    movl Y(%esi), %ecx                                  # find y position 
    shrl $SHIFTBITS, %ecx
    imull $YOFFSET, %ecx, %ecx
    addl %ecx, %eax 
	xorb %cl, %cl
    movb $ERASE, %cl 
	pushl %esi
    call mp1_poke										# erase explosion from the screen 
	popl %esi
	
remove_missile:								
    cmp mp1_missile_list, %esi					# check if it's the head of the list that need to remove
    je remove_head
	
	movl mp1_missile_list, %ecx
	
find_previous:									# find the pointer of the previous missile
	cmpl (%ecx), %esi
	je remove
	movl (%ecx), %ecx
	jmp find_previous
	
remove:											# remove missile 
    movl (%esi), %ebx
    movl %ebx, (%ecx)
    pushl %ecx
    pushl %esi
    call mp1_free
    popl %esi
    popl %ecx
    movl (%ecx), %esi
    jmp list_traversal 
        
  
remove_head:								# is need to remove the head of the list, change the head to the next 
    movl (%esi), %ecx
    movl %ecx, mp1_missile_list
    pushl %esi
    call mp1_free
    popl %esi
    movl mp1_missile_list, %esi
    jmp list_traversal
    
	
link_finished:                               # traversal link finished        
	popl %edi
    popl %esi
    popl %ebx
	leave
	ret

# cities_check
# this function check weither the cities is alive or not, and draw with the proper base pic
# input: base_alive, base_pic, dead_base_pic
# output: N/A
############################################
cities_check:
	pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    pushl %esi
    pushl %edi
	
	movl base_alive, %ecx                                   # ecx holds base_alive array
    movl $5, %ebx                                           # ebx holds number of chars drawing as a counter
    movl $FIRST, %edx                                           # edx holds start loction of cities, 18 for city 20
    cmpb $0, %cl                                            # check city 20
    je dead_city
    jne draw_city
    
check_40:                                                   # check city 40
    movl $5, %ebx
    movl $SECOND, %edx
    cmpb $0, %ch
    je dead_city
    jne draw_city
    
check_60:                                                   # check city 60
    movl $5, %ebx
    movl $THRID, %edx
    shrl $SHIFTBITS, %ecx                                          # right shift ebx to get city 60
    cmpb $0, %cl
    je dead_city
    jne draw_city
    
dead_city:
    xorl %esi, %esi                     
    leal dead_base_pic, %esi                                # esi holds dead_base_pic
    jmp city_draw_loop
    
draw_city:
    xorl %esi, %esi
    leal base_pic, %esi                                     # esi holds base_pic
    
city_draw_loop: 
    movb (%esi), %cl 
    xorl %eax, %eax                                                 
    imull $2, %edx, %eax                                    # column offset = 2*startlocation
    addl $ROWOFFSET, %eax                                        # row offset: 24 row *160 byes
    pushl %edx
    call mp1_poke											# draw the city with base_pic or base_dead_pic
    popl %edx
	addl $-1, %ebx
    inc %edx                                                # increment x position
    inc %esi                                                # next char
    cmpl $0, %ebx
    jne city_draw_loop
	
check_next_city:
    cmpl $43, %edx                                          # check which city should be next
    jl check_40
    cmpl $63, %edx
    jl check_60
	
    popl %edi
    popl %esi
    popl %ebx
    leave
    ret
	
# draw_crosshair
# this function draws the crosshair
# input: crosshairs_x, crosshairs_y
# output: N/A
###############
draw_crosshair:
	pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    pushl %esi
    pushl %edi
	
	xorl %eax, %eax 							# the crosshair x
	imull $2, crosshairs_x, %eax
    xorl %ecx, %ecx
    imull $YOFFSET, crosshairs_y, %ecx			# the crosshair y
    addl %ecx, %eax								# draw the cross hair 
	movb $CROSSHAIR, %cl
	call mp1_poke
	
    popl %edi
    popl %esi
    popl %ebx
    leave
    ret
	
# mp1_ioct1_startgame
# this function initialize all values and start the game
# input: N/A
# output: 0 - success	
######################################
mp1_ioctl_startgame:
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    pushl %esi
    pushl %edi
                                                           # initializetions
    movl $CROSSX, crosshairs_x                                 # initialize crosshair coordinates
    movl $CROSSY, crosshairs_y
    movl $0, mp1_missile_list                               # missile_list set to 0
    movl $0, mp1_score                                      # mp1_score set to 0
    movl $BASEALIVE, base_alive                            # base_alive set to 1
    
    popl %edi
    popl %esi
    popl %ebx
    leave
		ret
		
# mp1_ioctl_addmissile
# this function add the missiles (user) into the kernel space	
# input: pointer to the user space missile	
# return value: 0 - success, -1 - fail
#########################################
mp1_ioctl_addmissile:
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    pushl %esi
    pushl %edi
    
    cmpl $0, 8(%ebp)                                        # check null pointer
    je NULL_PTR                                             # return null
    
    pushl $33                                               # totally 33 bits for malloc argument
    call mp1_malloc                                         # dynamic allocation
    cmpl $0, %eax
    je NULL_PTR
    
    pushl $33                                                # mp1_copy_from_user argument
    push 8(%ebp)
    pushl %eax
    call mp1_copy_from_user 						# copy it into kernal space
    cmpl $0, %eax
    jne errors                                              # maybe je errors
    popl %eax
	popl 8(%ebp)
	
	movl mp1_missile_list, %ecx 					# update linked list
	movl %ecx, (%eax)
	movl %eax, mp1_missile_list
	xorl %eax, %eax
	jmp add_return 
	
    
NULL_PTR:
    movl $-1, %eax
    jmp add_return
    
errors:
    popl %eax 
    popl 8(%ebp)                   
    pushl %eax
    call mp1_free
    popl %eax                       
    movl $-1, %eax
    
add_return:    
    popl %edi
    popl %esi
    popl %ebx
    leave
		ret
		
		
# mp1_ioct1_movexhairs
# this function is use to updates the movexhairs
# input: 32 bit integer contains two signed 16 bit intergers as low and high words
# output: 0
######################################
mp1_ioctl_movexhairs:
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    pushl %esi
    pushl %edi
    
    movb $ERASE, %cl                        # erase crosshair first, then check next step
    imull $2, crosshairs_x, %eax
    imull $YOFFSET, crosshairs_y, %ebx
    addl %ebx, %eax
    call mp1_poke
                                            
    movl 8(%ebp), %ebx                      # ebx holds 32 bit date
    addw %bx, crosshairs_x                  # update crosshairs x loccation
    shrl $SHIFTBITS, %ebx                          # shift 16 bits to get delta y
    addw %bx, crosshairs_y        
                        
check_range:                                # check x and y ranges 
    cmpl $0, crosshairs_x                   # x position check    
    jl x_under
    cmpl $XMOST, crosshairs_x
    jg x_above
    cmpl $0, crosshairs_y
    jl y_under
    cmpl $YMOST, crosshairs_y
    jg y_above
    jmp move_return
    
x_under:                                    # since crosshair x is below 0, set it to 0
    movl $0, crosshairs_x
	jmp check_range
x_above:
    movl $XMOST, crosshairs_x
	jmp check_range
y_under:
    movl $0, crosshairs_y
	jmp check_range
y_above:   
    movl $YMOST, crosshairs_y    
    jmp check_range
	
move_return:
	xorl %eax, %eax
    popl %edi
    popl %esi
    popl %ebx
    leave
		ret

# mp1_ioctl_getstatus
# this function retrieve the current score and the status of cities
# input: a 32 bit integer pointer in user space
# output: 0 - success, -1 - fail 
#####################################
mp1_ioctl_getstatus:
	pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    pushl %esi
    pushl %edi	 
    
    cmpl $0, 8(%ebp) # check if it's null, if so, return -1
    je false_return
    
    movl $4, %ecx                   # dynamically allocate 4 bytes space
    pushl %ecx
    call mp1_malloc
    cmpl $0, %eax
    popl %ecx
    movl %eax, allocate_address
    je false_return
    
    xorl %edx, %edx                 # edx will holds scare and city status
    xorl %ebx, %ebx
    movl base_alive, %ebx           # ebx holds base_alive
    cmpb $0, %bl                    # check city 20 status
    jne city_20_alive
check_40_status:    
    cmpb $0, %bh                    # check city 40 status
    jne city_40_alive
check_60_status:    
    shrl $SHIFTBITS, %ebx                  # check city 60 status
    cmpb $0, %bl
    jne city_60_alive
    jmp save_score
    
city_20_alive:
    addl $1, %edx
    jmp check_40_status
city_40_alive:
    addl $2, %edx
    jmp check_60_status
city_60_alive: 
    addl $4, %edx
       
save_score:
    shll $16, %edx                      # left shift edx to save score
    movw mp1_score, %dx
    	
	movl %edx, allocate_address;

    pushl $4
    pushl $allocate_address
    pushl 8(%ebp)
    call mp1_copy_to_user
	add $12, %esp
    cmpl $0, %eax
    jne false_return
    jmp status_return

false_return:
    movl $-1, %eax
    popl %edx
    popl %edi
    popl %esi
    leave
		ret
  
status_return:
    xorl %eax, %eax
    popl %edx
    popl %edi
    popl %esi
    leave
		ret
		
		
# mp1_ioctl_endgame:
# this function is to do cleanup work at the end of game
# input: N/A
# output: 0 - success
###############################
mp1_ioctl_endgame:
    pushl %ebp
    movl %esp, %ebp
    pushl %ebx
    pushl %esi
    pushl %edi
 
    movl mp1_missile_list, %esi                 # esi holds head of the linked lsit
    
cleaning:
    cmpl $0, %esi                               # if linked list is empty, then it's the end
    je endgame_return
    pushl (%esi)                           		# save the next one before call free, thus, it won't get lost 
    pushl %esi
    call mp1_free                               # free it
	addl $4, %esp
    popl %esi
    jmp cleaning
    
endgame_return:
    movl $0, %eax                               # return 0 when cleaned
    popl %edi
    popl %esi
    popl %ebx
    leave
	ret
