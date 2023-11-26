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
	BASEALIVE = 0x00FFFFFF #
	CROSSHAIR = 43 # ASCII + FOR MY CROSSHAIR
    ROW_OFFSET_1 = 3876 # math = [24(rast col)*160] + [18(base 1 row)*2] = 3876
    ROW_OFFSET_2 = 3916 # math = [24(rast col)*160] + [38(base 1 row)*2] = 3916
    ROW_OFFSET_3 = 3956 # math = [24(rast col)*160] + [58(base 1 row)*2] = 3956
	XMAX = 79 # max possible for X
	XOFF = 2 # max possible for Y
	YOFF = 160 
	YMAX = 24
	SPACECHAR = 32 # ASCII FOR MY BLANK
	SHIFTING = 16
	CROSSHAIR_X_MIDDLE = 40 # CENTER
	CROSSHAIR_Y_MIDDLE = 12 # CENTER


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
	pushl %ebp
	movl %esp,%ebp

	pushl %ebx
	pushl %esi
	pushl %edi	

	call update_missiles #CALL TO Tasklet 1
	
	popl %edi
	popl %esi
	popl %ebx

	pushl %ebx
	pushl %esi
	pushl %edi

	call redraw_bases #CALL TO Taasklet 2
	
	popl %edi
	popl %esi
	popl %ebx

	pushl %ebx
	pushl %esi
	pushl %edi

	call redraw_crosshairs #CALL TO Tasklet 3
	
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
	movl 8(%esp), %ecx 
	cmpl $0, %ecx #cmd value check for less than 0
	jl invalid_command 
	cmpl $4, %ecx
	jg invalid_command #cmd value check for greater than 4, they work for 0,1,2,3,4
	jmp *jump_table(,%ecx,4)
		ret
	invalid_command:
		movl $-1, %eax
			ret
	jump_table:
	.long mp1_ioctl_startgame, mp1_ioctl_addmissile, mp1_ioctl_movexhairs, mp1_ioctl_getstatus, mp1_ioctl_endgame


# ----------------- Functions private to this file -------------------
 

#----------------------------------------------------------------------TASKLET START------------------------------------------------------------------------------#


#-------------------------------------------------------------------works-----------------------------------------------------------------------------#
#TASKLET 1
# void update_missiles()
# This is my main function where my job is to traverese throught the linked list of missiles, meanwhile checking some key attributes:
# a. its postion at a lot of given conditions (i. if exploded      ii. if it chilling on some trijectory with no impact      iii. impact)
# b. on imact draw the explosion anf remove it from the screen
# c. manage the main remove from the linked listt and interate again if need-be
# input: none
# output: none
#TASKLET 1
update_missiles:
	pushl %ebp																		
	movl %esp, %ebp																	
	pushl %ebx #callee	save															
	pushl %esi #callee save
	pushl %edi #callee save

	movl  mp1_missile_list,%ebx

	missile_list_traverasl:
		cmpl  $0,%ebx #check for empty list
		je end_update_missiless #tear , base case

	update_x_y_pos_and_clear:
		movl X(%ebx),%eax
		movl Y(%ebx),%esi

		shrl $SHIFTING,%eax
		shrl $SHIFTING,%esi

		imull $XOFF,%eax
		imull $YOFF,%esi

		addl %esi,%eax #location to draw

		movb $SPACECHAR,%cl #space character SPACECHAR

		pushl %edx
		call mp1_poke #DRAW
		popl %edx

		#now check if it missile is exploded like the doc. ie,further check: note still in the missile_list_traversl coz this is an atrribute i check for updated list(necxt)
		cmpl $0,EXPLODED(%ebx) 
		jne actually_explode # coz explosion only happens on non 0
		je update_missile_location

	update_missile_location:
		movl VX(%ebx),%ecx
		addl X(%ebx),%ecx
		shrl $SHIFTING,%ecx
		cmpl $0,%ecx
		jl  mp1_remove_missile
		cmpl $XMAX,%ecx
		jg  mp1_remove_missile

		movl VY(%ebx),%ecx
		addl Y(%ebx),%ecx
		shrl $SHIFTING,%ecx
		cmpl $0,%ecx
		jl  mp1_remove_missile
		cmpl $YMAX,%ecx
		jg  mp1_remove_missile

	new_location:
		movl VX(%ebx),%ecx
		addl  %ecx,X(%ebx) #add VX to X
		movl VY(%ebx),%ecx
		addl  %ecx,Y(%ebx) #add VY to Y

	check_exploded_dest:
		movl X(%ebx),%ecx
		shrl $SHIFTING, %ecx
		movl DEST_X(%ebx),%esi
		cmpl %ecx,%esi #see if its at explosion point X, if not drae missile 
		jne actually_draw_missile

		movl Y(%ebx),%ecx
		shrl $SHIFTING, %ecx
		movl DEST_Y(%ebx),%esi
		cmpl %ecx,%esi #see if its at explosion point Y, if not drae missile 
		je actually_explode
		jne actually_draw_missile
		
	actually_draw_missile:
		movl X(%ebx),%eax
		movl Y(%ebx),%esi

		shrl $SHIFTING,%eax
		shrl $SHIFTING,%esi

		imull $XOFF,%eax
		imull $YOFF,%esi

		addl %esi,%eax #location to draw missile character

		movb C(%ebx),%cl #Missile charchter

		pushl %edx
		call mp1_poke #draw it 
		popl %edx

		#now remeber to update list i forgot to do that:
		movl NEXT(%ebx),%ebx
		jmp missile_list_traverasl


	actually_explode:
		movl X(%ebx),%eax
		movl Y(%ebx),%esi

		shrl $SHIFTING,%eax
		shrl $SHIFTING,%esi

		imull $XOFF,%eax
		imull $YOFF,%esi

		addl %esi,%eax

		movb $EXPLOSION,%cl #draw explosion character

		pushl %edx
		call mp1_poke
		popl %edx

	check_no_notify_user:
		push %ebx
		call missile_explode
		popl %ebx
		cmpl $0,%eax #checking if the result of that call is 0 to decide to notify or not notify
		je mp1_dont_notify_user
		call mp1_notify_user

	mp1_dont_notify_user:
		decl EXPLODED(%ebx) #decrementing value
		cmpl $0,EXPLODED(%ebx)
		je erase_it #if ecploded erase it ie. draw space
		movl NEXT(%ebx),%ebx #updatye
		jmp  missile_list_traverasl #back to list

	erase_it:
		movl X(%ebx),%eax
		movl Y(%ebx),%esi

		shrl $SHIFTING,%eax
		shrl $SHIFTING,%esi

		imull $XOFF,%eax
		imull $YOFF,%esi

		addl %esi,%eax #location to draw the space based off of previous condition

		movb $SPACECHAR,%cl #drawing spcae based off of the previous condition

		pushl %edx
		call mp1_poke #call for drawing
		popl %edx

	mp1_remove_missile:		
		cmpl mp1_missile_list,%ebx
		je remove_head_of_list
		movl mp1_missile_list,%esi

	remove_previous:
		cmpl NEXT(%esi),%ebx # checck previous
		je remove_from_list
		movl NEXT(%esi),%esi
		jmp remove_previous #looping back to do the same

	remove_from_list:
		movl NEXT(%ebx),%edx
		movl %edx,NEXT(%esi)

	free_memory_1:
		pushl %esi
		pushl %ebx
		call mp1_free
		popl %ebx
		popl %esi
		movl NEXT(%esi),%ebx #updating list
		jmp back_to_start

	back_to_start:
		jmp missile_list_traverasl #back to list in the start


	remove_head_of_list:
		movl NEXT(%ebx),%esi #nect ptr
		movl  %esi,mp1_missile_list #head

	free_memory_2:
		pushl %ebx
		call mp1_free #freeing it
		popl %ebx 
		movl mp1_missile_list,%ebx
		jmp back_to_start

	end_update_missiless:
		popl %edi #callee tear
		popl %esi #callee tear
		popl %ebx #callee tear

		leave
			ret
#-------------------------------------------------------------------works-----------------------------------------------------------------------------#
#-------------------------------------------------------------------works-----------------------------------------------------------------------------#
#TASKLET 2
# void redraw_bases()
# This function is used to check if my bases are dead or alive and draw them accordingly
# It finnally draws the apporopriate base_pic based off the answer to the prev question- dead or alive!!
# input   : none
# output  : none
redraw_bases:
	pushl %ebp																		
	movl %esp, %ebp		

	pushl %ebx #callee	save															
	pushl %esi #callee save
	pushl %edi #callee save

    base_1:
        movl $0, %esi
        movl base_alive,%edx
        andl $0x0ff, %edx
        movl $ROW_OFFSET_1, %eax #has the calulated location to draw
        cmpl $0, %edx #checking if the result of that shift is 0
        je dead_base_1 
        jne base_alive_1

    base_alive_1:
        leal base_pic, %ebx
        jmp print_1

    dead_base_1:
        leal dead_base_pic, %ebx
		print_1:
			movb (%esi,%ebx,1), %cl
			pushl %edx
			call mp1_poke
			popl %edx
			incl %esi #incremnt counter
			addl $2, %eax
			cmpl $5, %esi #coz has to less than my 5 char limit of the pic so looping back if not reached
			jb print_1

    base_2:
        movl $0, %esi
        movl base_alive,%edx
        andl $0xff00, %edx
        movl $ROW_OFFSET_2, %eax #has the calulated location to draw
        cmpl $0, %edx #checking if the result of that shift is 0
        je dead_base_2
        jne base_alive_2

    base_alive_2:
        leal base_pic, %ebx
        jmp print_2

    dead_base_2:
        leal dead_base_pic, %ebx
        print_2:
            movb (%ebx,%esi,1), %cl
            pushl %edx
            call mp1_poke
            popl %edx
            incl %esi #incremnt counter
            addl $2, %eax
            cmpl $5, %esi #coz has to less than my 5 char limit of the pic so looping back if not reached
            jb print_2

    base_3:
        movl $0, %esi
        movl base_alive,%edx
        andl $0xff0000, %edx
        movl $ROW_OFFSET_3, %eax #has the calulated location to draw
        cmpl $0, %edx #checking if the result of that shift is 0
        je dead_base_3
        jne base_alive_3

    base_alive_3:
        leal base_pic, %ebx 
        jmp print_3

    dead_base_3:
        leal dead_base_pic, %ebx
        print_3:
            movb (%ebx,%esi,1), %cl 
            pushl %edx
            call mp1_poke
            popl %edx
            incl %esi #incremnt counter
            addl $2, %eax
            cmpl $5, %esi #coz has to less than my 5 char limit of the pic so looping back if not reached
            jb print_3

	popl %edi #callee tear
	popl %esi #callee tear
	popl %ebx #callee tear

	leave
		ret

#-------------------------------------------------------------------works-----------------------------------------------------------------------------#
#-------------------------------------------------------------------works-----------------------------------------------------------------------------#
#TASKLET 3 works

# void redraw_crosshairs();
# This function draws the crosshair at the start of the game ie. makes sense to be in the tasklets, using its constant update at high speeds for the
# crosshairs to show up at the game load
# input: none
# output: none
redraw_crosshairs:
	pushl %ebp					
	movl %esp, %ebp	
	
	pushl %ebx #callee save
    pushl %esi
    pushl %edi

	movl (crosshairs_x), %edi
	movl (crosshairs_y), %esi

    #Calculate memory offset for crosshair update
    imull $XOFF, %edi       # Multiply x by 2 
    imull $YOFF, %esi     # Multiply y by 160
    addl %esi, %edi      # Add y to x
    movl %edi,%eax #to draw
	movb $CROSSHAIR, %cl #draw new crosshairs 43
	pushl %edx
	call mp1_poke
	popl %edx

	popl %edi
	popl %esi
	popl %ebx

	leave	
		ret
#-------------------------------------------------------------------works-----------------------------------------------------------------------------#
#----------------------------------------------------------------------TASKLET START------------------------------------------------------------------------------#
#-------------------------------------------------------------------works-----------------------------------------------------------------------------#
# int mp1_ioct1_startgame(unsigned long ignore)
# This function helps intialize all my thing sat the start of the game:
# things like: missile_list, crosshair to the center of the screen, score to zero and bases to be alive.
# HAVE FUN PLAYING MY GAME!!! Good Luck soldier!! ~ Pranav Nagarajan /^^^^\ /^^^^\ /^^^^\ <- if you know you know!!!
# input: none
# output: none
mp1_ioctl_startgame:
	pushl %ebp
	movl %esp,%ebp

	pushl %ebx #calee save
	pushl %esi
	pushl %edi

	movl $CROSSHAIR_X_MIDDLE, (crosshairs_x)		#setting crosshair x to 40
	movl $CROSSHAIR_Y_MIDDLE, (crosshairs_y) 		#setting crosshair y to 12
	movl $0, mp1_missile_list 
	movl $BASEALIVE, base_alive #setting all bases to be alove
	movl $0, mp1_score 

	popl %edi #teardown
	popl %esi
	popl %ebx

	leave
		ret
#-------------------------------------------------------------------works-----------------------------------------------------------------------------#

#-------------------------------------------------------------------works-----------------------------------------------------------------------------#
# int mp1_ioctl_addmissile(struct missile* user_missile)
# Thisn fuunction helps add missile inot the actual kernel
# input: pointer to the user missile 
# output: 0 , -1 : for success and failure respectively
mp1_ioctl_addmissile:
    pushl %ebp
    movl %esp, %ebp

    pushl %ebx #calee save
    pushl %esi
    pushl %edi

	movl 8(%ebp), %ebx

	pushl %ecx
    pushl $33 # size of missile struct
    call mp1_malloc # malloc(33)
	addl $4,%esp
	popl %ecx


    cmpl $0, %eax # check if it is returning 0
    je fail

	pushl %eax
	pushl %ecx
    pushl $33             # arg size of struct
	pushl %ebx
    pushl %eax # old
    call mp1_copy_from_user # copy to kernel space
	addl $12,%esp #restore stack
	popl %ecx

    cmpl $0, %eax
    jne negative_1_and_free

	when_it_didnt_fail:
		popl %eax
		movl mp1_missile_list, %ecx # was told not to do mem-me change that
		movl %ecx,NEXT(%eax)
		movl %eax, mp1_missile_list
		movl $0, %eax # clear it
		jmp addmissile_finish

	negative_1_and_free:
		popl %eax
		PUSHL %eax
		call mp1_free #asked to call free to free it, keep psuhes in mind to save needed values
		popl %eax
		movl $-1, %eax #result
		jmp addmissile_finish

	fail:
		movl $-1, %eax
		jmp addmissile_finish

	addmissile_finish:
		popl %edi #teardown
		popl %esi
		popl %ebx
		
		leave
			ret
#-------------------------------------------------------------------works-----------------------------------------------------------------------------#

#-------------------------------------------------------------------works-----------------------------------------------------------------------------#
# int mp1_ioctl_movexhairs(unsigned long xhair delta packed)
# This fuunction helps to update, move, and redraw my crosshairs!!! <- time to sharpen your aim!
# input: long crosshair coordinates gibem to us
# output: 0
mp1_ioctl_movexhairs:
    pushl %ebp          
    movl %esp, %ebp    

    pushl %ebx           # calee Save registers
    pushl %esi
    pushl %edi

    #Load the current crosshair x and y positions
    movl (crosshairs_x),%edi
    movl (crosshairs_y),%esi

    #Calculate memory offset for crosshair update
    imull $XOFF,%edi       # Multiply x by 2 
    imull $YOFF,%esi     # Multiply y by 160 
    addl %esi, %edi      # Add y to x

    movl %edi,%eax

    #Setting the character at the old crosshair position to a space
    movb $SPACECHAR,%cl        # ASCII code for space

    pushl %edx           # Save edx
    call mp1_poke        # function to update the screen
    popl %edx            # Restore edx

    #Extract x and y component changes from the parameter
    movl 8(%ebp),%ebx   #Extract the lower 16 bits as x changE
    movl 8(%ebp),%ecx   # Extract the higher 16 bits as y change
    movswl %bx,%ebx
    sarl $SHIFTING,%ecx       # Shift right to get the signed value

    #Add x and y component changes to crosshair x and y positions
    movl (crosshairs_x),%edi
    addl %ebx, %edi
    movl (crosshairs_y),%esi
    addl %ecx,%esi

	crosshair_limit_check: #Ensure crosshair coordinates stay within limits
		cmp $0,%edi  # Compare x with 0
		jl min_x              # If less than 0, jump to min_x
		cmp $XMAX,%edi # Compare x with 79
		jg max_x              # If greater than 79, jump to max_x
		jmp check_y

	check_y:
		cmp $0, %esi  # Compare y with 0
		jl min_y              # If less than 0, jump to min_y
		cmp $YMAX, %esi # Compare y with 24
		jg max_y              # If greater than 24, jump to max_y
		jmp drawing_again       

	min_x:
		movl $0,%edi  # Set x to 0
		jmp check_y   
	max_x:
		movl $XMAX,%edi # Set x to 79
		jmp check_y   

	min_y:
		movl $0, %esi  # Set y to 0
		jmp drawing_again   # Jump back 
	max_y:
		movl $YMAX, %esi # Set y to 24
		jmp drawing_again

	drawing_again:
		movl  %esi, (crosshairs_y)
		movl  %edi, (crosshairs_x)
		imull $XOFF,%edi       # Multiply x by 2
		imull $YOFF,%esi     # Multiply y by 160
		addl %esi,%edi      # Add y to x

		movl %edi,%eax #to save draw loaction

		#Set the character at the old crosshair position to a space
		movb $CROSSHAIR,%cl        # ASCII code for crossjair
		pushl %edx           # Save edx
		call mp1_poke    
		popl %edx            # Restore edx

		popl %edi #callee tear
		popl %esi
		popl %ebx
		movl $0,%eax       # Return 0

		leave
			ret
#------------------------------------------------------------wroks------------------------------------------------------------------------------------#
#-------------------------------------------------------------------works-----------------------------------------------------------------------------#
# void mp1_ioctl_getstatus(unsigned long* user_status)
# This function helps us get the current score and check the staus of my cities
# Better keep our cities safe from those sneaky enemy missile!!!! Good Luck!!
# input: lon user_status
# output: 0 , -1 for success and failure respectively
mp1_ioctl_getstatus:
	pushl %ebp
	movl %esp, %ebp

	pushl %ebx #callee save
	pushl %esi
	pushl %edi

	movl 8(%ebp), %ebx
	movl $0, %esi
	movl $0, %ecx
	movl base_alive, %edi
	shll $8, %edi #left shift

	life_loop:
		cmpl $3, %ecx #3bases
		jge life_done
		cmpl $0, %edi
		jnz base_live
		jmp base_dead

	base_live:
		addl $1, %ecx #count
		addl $1, %esi
		shll $1, %esi
		shll $8, %edi #left shift
		jmp life_loop

	base_dead:
		addl $1, %ecx
		shll $1, %esi
		shll $8, %edi #left shift
		jmp life_loop

	life_done:
		# Set the "livebit" by shifting the lower 0, 1, 2 bits to 16, 17, 18
		shll $15, %esi
		movl mp1_score, %edi #score load
		# Store esi in the lower word of edi (ready)
		movw %di, %si
		pushl %esi
		movl %esp, %eax

		# Call mp1_copy_to_user
		pushl %edx
		pushl %ecx

		pushl $4
		pushl %eax
		pushl %ebx
		call mp1_copy_to_user
		addl $12, %esp
		popl %ecx
		popl %edx
		popl %esi

		# Check if eax (return value) is not equal to 0 (failure)
		cmpl $0, %eax
		jnz ret_neg1
		# Success, set eax to 0
		movl $0, %eax
		# Restore callee-saved registers
		popl %edi
		popl %esi
		popl %ebx

		leave
			ret

	ret_neg1:
		movl $-1, %eax #-1 result 
		popl %edi #calle teadown
		popl %esi
		popl %ebx

		leave
			ret
#-------------------------------------------------------------------works-----------------------------------------------------------------------------#

#-------------------------------------------------------------------works-----------------------------------------------------------------------------#
#int mp1 ioctl endgame (unsigned long ignore)
# This function helps us get the current score and check the staus of my cities
# Ends the game and tearsdown
# Thanks for playing my game, hope you had fun!!! --PRANAV NAGARAJAN
# input: none
# output: doesnt matter 
mp1_ioctl_endgame:
    pushl %ebp
    movl %esp, %ebp

    pushl %ebx #calee save
    pushl %esi
    pushl %edi

	movl mp1_missile_list, %esi #eax head rn #used ti be ebx i forgot i had that beofre but matterrrrsssss

	Game_Ending_checker:
		cmpl $0, %esi               #sees if the list is empty
		je ending 					# best case hit the dip
		movl %esi, %edi
		movl NEXT(%esi), %edi       #goes to the next missile
		
		pushl %esi
		call mp1_free          
		addl $4, %esp 
		movl %edi, %esi             # restore pointer
		jmp Game_Ending_checker

	ending:
		movl $0, mp1_missile_list #optional but helps????
		popl %edi #callee teardown
		popl %esi
		popl %ebx

		leave
			ret
