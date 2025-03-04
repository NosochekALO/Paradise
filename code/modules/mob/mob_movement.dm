/client/verb/toggle_throw_mode()
	set hidden = 1
	if(iscarbon(mob))
		var/mob/living/carbon/C = mob
		C.toggle_throw_mode()
	else
		to_chat(usr, "<span class='danger'>Это существо не может бросать предметы.</span>")

/client/proc/Move_object(direct)
	if(mob.control_object.density)
		step(mob.control_object, direct)
		if(!mob.control_object)
			return
		mob.control_object.setDir(direct)
	else
		var/new_turf = get_step(mob.control_object, direct)
		if(new_turf)
			mob.control_object.forceMove(new_turf)


/client/Move(n, direct)
	if(world.time < move_delay)
		return

	input_data.desired_move_dir_add = NONE
	input_data.desired_move_dir_sub = NONE

	var/old_move_delay = move_delay
	move_delay = world.time + world.tick_lag //this is here because Move() can now be called multiple times per tick
	if(!mob || !mob.loc)
		return 0

	if(!n || !direct) // why did we never check this before?
		return FALSE

	if(HAS_TRAIT(mob, TRAIT_NO_TRANSFORM))
		return FALSE //This is sota the goto stop mobs from moving var

	if(mob.control_object)
		return Move_object(direct)

	if(!isliving(mob))
		return mob.Move(n, direct)

	if(mob.stat == DEAD)
		mob.ghostize()
		return 0

	if(SEND_SIGNAL(mob, COMSIG_MOB_CLIENT_PRE_LIVING_MOVE, n, direct) & COMSIG_MOB_CLIENT_BLOCK_PRE_LIVING_MOVE)
		return FALSE

	var/mob/living/L = mob	//Already checked for isliving earlier
	if(L.incorporeal_move)//Move though walls
		move_delay = world.time + 0.5 // cap to 20fps
		L.glide_size = 8
		Process_Incorpmove(direct)
		return FALSE

	if(mob.remote_control) //we're controlling something, our movement is relayed to it
		return mob.remote_control.relaymove(mob, direct)

	if(isAI(mob))
		if(istype(mob.loc, /obj/item/aicard))
			var/obj/O = mob.loc
			return O.relaymove(mob, direct) // aicards have special relaymove stuff
		return AIMove(n, direct, mob)

	if(Process_Grab())
		return

	if(mob.buckled) //if we're buckled to something, tell it we moved.
		return mob.buckled.relaymove(mob, direct)

	if(!(L.mobility_flags & MOBILITY_MOVE))
		return FALSE

	if(!mob.lastarea)
		mob.lastarea = get_area(mob.loc)

	if(isobj(mob.loc) || ismob(mob.loc)) //Inside an object, tell it we moved
		var/atom/O = mob.loc
		return O.relaymove(mob, direct)

	if(!mob.Process_Spacemove(direct))
		return 0

	if(SEND_SIGNAL(mob, COMSIG_MOB_CLIENT_PRE_MOVE, args) & COMSIG_MOB_CLIENT_BLOCK_PRE_MOVE)
		return FALSE

	if(HAS_TRAIT(mob, TRAIT_RESTRAINED) && mob.pulledby) // Why being pulled while cuffed prevents you from moving
		var/mob/puller = mob.pulledby
		if(!puller.incapacitated() && !HAS_TRAIT(puller, TRAIT_HANDS_BLOCKED) && mob.Adjacent(puller))
			to_chat(src, span_warning("Вы скованы и не можете пошевелиться!"))
			move_delay = world.time + 1 SECONDS
			return FALSE
		puller.stop_pulling()

	//We are now going to move
	current_move_delay = mob.cached_multiplicative_slowdown

	if(!istype(get_turf(mob), /turf/space) && mob.pulling)
		var/mob/living/M = mob
		var/mob/living/silicon/robot/R = mob
		if(!(STRONG in M.mutations) && !isconstruct(M) && !istype(M, /mob/living/simple_animal/hostile/clockwork) && !istype(M, /mob/living/simple_animal/hostile/guardian) && !(istype(R) && (/obj/item/borg/upgrade/vtec in R.upgrades))) //No slowdown for STRONG gene //Blood cult constructs //Clockwork constructs //Borgs with VTEC //Holopigs
			current_move_delay *= min(1.4, mob.pulling.get_pull_push_speed_modifier(current_move_delay))

	if(old_move_delay + world.tick_lag > world.time)
		move_delay = old_move_delay
	else
		move_delay = world.time
	mob.last_movement = world.time

	if(locate(/obj/item/grab, mob))
		current_move_delay += 7

	. = mob.SelfMove(n, direct, current_move_delay)
	mob.setDir(direct)

	if((direct & (direct - 1)) && mob.loc == n) //moved diagonally successfully
		current_move_delay *= SQRT_2 //Will prevent mob diagonal moves from smoothing accurately, sadly

	move_delay += current_move_delay

	if(mob.pulledby)
		mob.pulledby.stop_pulling()

	if(mob && .)
		if(mob.throwing)
			mob.throwing.finalize()

		for(var/obj/O in mob)
			O.on_mob_move(direct, mob)


/mob/proc/SelfMove(turf/n, direct, movetime)
	return Move(n, direct, movetime)

///Process_Grab()
///Called by client/Move()
///Checks to see if you are being grabbed and if so attemps to break it
/client/proc/Process_Grab()
	if(LAZYLEN(mob.grabbed_by))
		if(mob.incapacitated(INC_IGNORE_GRABBED)) // Can't break out of grabs if you're incapacitated
			return TRUE
		var/list/grabbing = list()

		if(istype(mob.l_hand, /obj/item/grab))
			var/obj/item/grab/G = mob.l_hand
			grabbing += G.affecting

		if(istype(mob.r_hand, /obj/item/grab))
			var/obj/item/grab/G = mob.r_hand
			grabbing += G.affecting

		for(var/X in mob.grabbed_by)
			var/obj/item/grab/G = X
			switch(G.state)

				if(GRAB_PASSIVE)
					if(!grabbing.Find(G.assailant)) //moving always breaks a passive grab unless we are also grabbing our grabber.
						qdel(G)

				if(GRAB_AGGRESSIVE)
					move_delay = world.time + 10
					if(!prob(25))
						return TRUE
					mob.visible_message("<span class='danger'>[mob] вырыва[pluralize_ru(mob.gender,"ется","ются")] из хватки [G.assailant]!</span>")
					qdel(G)

				if(GRAB_NECK)
					move_delay = world.time + 10
					if(!prob(5))
						return TRUE
					mob.visible_message("<span class='danger'>[mob] вырыва[pluralize_ru(mob.gender,"ется","ются")] из захвата головы [G.assailant]!</span>")
					qdel(G)
	return FALSE


///Process_Incorpmove
///Called by client/Move()
///Allows mobs to run though walls
/client/proc/Process_Incorpmove(direct)
	var/turf/mobloc = get_turf(mob)
	if(!isliving(mob))
		return
	var/mob/living/L = mob
	switch(L.incorporeal_move)
		if(INCORPOREAL_NORMAL)
			L.forceMove(get_step(L, direct))
			L.dir = direct
		if(INCORPOREAL_NINJA)
			if(prob(50))
				var/locx
				var/locy
				switch(direct)
					if(NORTH)
						locx = mobloc.x
						locy = (mobloc.y+2)
						if(locy>world.maxy)
							return
					if(SOUTH)
						locx = mobloc.x
						locy = (mobloc.y-2)
						if(locy<1)
							return
					if(EAST)
						locy = mobloc.y
						locx = (mobloc.x+2)
						if(locx>world.maxx)
							return
					if(WEST)
						locy = mobloc.y
						locx = (mobloc.x-2)
						if(locx<1)
							return
					else
						return
				L.glide_size = L.glide_size * 2
				L.forceMove(locate(locx,locy,mobloc.z))
				spawn(0)
					var/limit = 2//For only two trailing shadows.
					for(var/turf/T as anything in get_line(mobloc, L.loc))
						new /obj/effect/temp_visual/dir_setting/ninja/shadow(T, L.dir)
						limit--
						if(limit<=0)
							break
			else
				new /obj/effect/temp_visual/dir_setting/ninja/shadow(mobloc, L.dir)
				L.forceMove(get_step(L, direct))
			L.dir = direct
		if(INCORPOREAL_REVENANT) //Incorporeal move, but blocked by holy-watered tiles
			var/turf/simulated/floor/stepTurf = get_step(L, direct)
			if(stepTurf.flags & NOJAUNT)
				to_chat(L, span_warning("Святые силы блокируют ваш путь."))
				ADD_TRAIT(L, TRAIT_NO_TRANSFORM, INCORPOREAL_TRAIT)
				spawn(2)
					REMOVE_TRAIT(L, TRAIT_NO_TRANSFORM, INCORPOREAL_TRAIT)
			else
				L.forceMove(get_step(L, direct))
				L.dir = direct
	return 1


/**
 * Handles mob/living movement in space (or no gravity)
 *
 * Called by /client/Move()
 *
 * return TRUE for movement or FALSE for none
 *
 * You can move in space if you have a spacewalk ability
 */
/mob/Process_Spacemove(movement_dir = NONE)
	. = ..()
	if(.)
		return .

	if(buckled)
		return TRUE

	var/atom/movable/backup = get_spacemove_backup(movement_dir)
	if(!backup)
		return FALSE

	if(!istype(backup) || !movement_dir || backup.anchored)
		return TRUE

	// last pushoff exists for one reason
	// to ensure pushing a mob doesn't just lead to it considering us as backup, and failing
	last_pushoff = world.time
	if(backup.newtonian_move(REVERSE_DIR(movement_dir))) //You're pushing off something movable, so it moves
		// We set it down here so future calls to Process_Spacemove by the same pair in the same tick don't lead to fucky
		backup.last_pushoff = world.time
		to_chat(src, span_info("Вы отталкиваетесь от [backup] для продолжения движения."))

	return TRUE


/mob/get_spacemove_backup(moving_direction)
	for(var/atom/pushover as anything in range(1, get_turf(src)))
		if(pushover == src)
			continue
		if(isarea(pushover))
			continue
		if(isturf(pushover))
			var/turf/turf = pushover
			if(isspaceturf(turf))
				continue
			if(!turf.density && !mob_negates_gravity())
				continue
			return turf

		var/atom/movable/rebound = pushover
		if(rebound == buckled)
			continue

		if(ismob(rebound))
			var/mob/lover = rebound
			if(lover.buckled)
				continue

		var/pass_allowed = rebound.CanPass(src, get_dir(rebound, src))
		if(!rebound.density && pass_allowed)
			continue
		//Sometime this tick, this pushed off something. Doesn't count as a valid pushoff target
		if(rebound.last_pushoff == world.time)
			continue
		/*
		if(continuous_move && !pass_allowed)
			var/datum/move_loop/move/rebound_engine = SSmove_manager.processing_on(rebound, SSspacedrift)
			// If you're moving toward it and you're both going the same direction, stop
			if(moving_direction == get_dir(src, pushover) && rebound_engine && moving_direction == rebound_engine.direction)
				continue
		else if(!pass_allowed)
			if(moving_direction == get_dir(src, pushover)) // Can't push "off" of something that you're walking into
				continue
		*/
		if(rebound.anchored)
			return rebound
		if(pulling == rebound)
			continue
		return rebound


/mob/has_gravity(turf/gravity_turf)
	if(!isnull(GLOB.gravity_is_on))	// global admin override.
		return GLOB.gravity_is_on
	return mob_negates_gravity() || ..()


/**
 * Does this mob ignore gravity
 */
/mob/proc/mob_negates_gravity()
	return FALSE


/mob/proc/Move_Pulled(atom/target)
	if(HAS_TRAIT(src, TRAIT_RESTRAINED) || !pulling)
		return
	if(isliving(src))	// temporary
		var/mob/living/l_mob = src
		if(!(l_mob.mobility_flags & MOBILITY_MOVE))
			return
	if(pulling.anchored || pulling.move_resist > move_force || !pulling.Adjacent(src))
		stop_pulling()
		return
	if(isliving(pulling))
		var/mob/living/living_pulling = pulling
		if(living_pulling.buckled?.buckle_prevents_pull) //if they're buckled to something that disallows pulling, prevent it
			stop_pulling()
			return
	if(target == loc && pulling.density)
		return
	var/pull_dir = get_dir(pulling.loc, target)
	if(!Process_Spacemove(pull_dir))
		return
	if(isobj(pulling))
		var/obj/object = pulling
		if(object.obj_flags & BLOCKS_CONSTRUCTION_DIR)
			var/obj/structure/window/window = object
			var/fulltile = istype(window) ? window.fulltile : FALSE
			if(!valid_build_direction(get_step(object, pull_dir), object.dir, is_fulltile = fulltile))
				return
	pulling.Move(get_step(pulling.loc, pull_dir), pull_dir, glide_size)


/client/proc/check_has_body_select()
	return mob && mob.hud_used && mob.hud_used.zone_select && istype(mob.hud_used.zone_select, /atom/movable/screen/zone_sel)

/client/verb/body_toggle_head()
	set name = "body-toggle-head"
	set hidden = 1

	if(!check_has_body_select())
		return

	var/next_in_line
	switch(mob.zone_selected)
		if(BODY_ZONE_HEAD)
			next_in_line = BODY_ZONE_PRECISE_EYES
		if(BODY_ZONE_PRECISE_EYES)
			next_in_line = BODY_ZONE_PRECISE_MOUTH
		else
			next_in_line = BODY_ZONE_HEAD

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(next_in_line)

/client/verb/body_r_arm()
	set name = "body-r-arm"
	set hidden = 1

	if(!check_has_body_select())
		return

	var/next_in_line
	if(mob.zone_selected == BODY_ZONE_R_ARM)
		next_in_line = BODY_ZONE_PRECISE_R_HAND
	else
		next_in_line = BODY_ZONE_R_ARM

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(next_in_line)

/client/verb/body_chest()
	set name = "body-chest"
	set hidden = 1

	if(!check_has_body_select())
		return

	var/next_in_line
	if(mob.zone_selected == BODY_ZONE_CHEST)
		next_in_line = BODY_ZONE_WING
	else
		next_in_line = BODY_ZONE_CHEST

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(next_in_line)

/client/verb/body_l_arm()
	set name = "body-l-arm"
	set hidden = 1

	if(!check_has_body_select())
		return

	var/next_in_line
	if(mob.zone_selected == BODY_ZONE_L_ARM)
		next_in_line = BODY_ZONE_PRECISE_L_HAND
	else
		next_in_line = BODY_ZONE_L_ARM

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(next_in_line)

/client/verb/body_r_leg()
	set name = "body-r-leg"
	set hidden = 1

	if(!check_has_body_select())
		return

	var/next_in_line
	if(mob.zone_selected == BODY_ZONE_R_LEG)
		next_in_line = BODY_ZONE_PRECISE_R_FOOT
	else
		next_in_line = BODY_ZONE_R_LEG

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(next_in_line)

/client/verb/body_groin()
	set name = "body-groin"
	set hidden = 1

	if(!check_has_body_select())
		return

	var/next_in_line
	if(mob.zone_selected == BODY_ZONE_PRECISE_GROIN)
		next_in_line = BODY_ZONE_TAIL
	else
		next_in_line = BODY_ZONE_PRECISE_GROIN

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(next_in_line)

/client/verb/body_tail()
	set name = "body-tail"
	set hidden = 1

	if(!check_has_body_select())
		return

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(BODY_ZONE_TAIL)

/client/verb/body_l_leg()
	set name = "body-l-leg"
	set hidden = 1

	if(!check_has_body_select())
		return

	var/next_in_line
	if(mob.zone_selected == BODY_ZONE_L_LEG)
		next_in_line = BODY_ZONE_PRECISE_L_FOOT
	else
		next_in_line = BODY_ZONE_L_LEG

	var/atom/movable/screen/zone_sel/selector = mob.hud_used.zone_select
	selector.set_selected_zone(next_in_line)

/client/verb/toggle_walk_run()
	set name = "toggle-walk-run"
	set hidden = TRUE
	set instant = TRUE
	if(mob)
		mob.toggle_move_intent()


/mob/proc/toggle_move_intent()
	return

/mob/verb/move_up()
	set name = "Move Upwards"
	set category = "IC"

	if(remote_control)
		return remote_control.relaymove(src, UP)

	var/turf/current_turf = get_turf(src)
	var/turf/above_turf = GET_TURF_ABOVE(current_turf)

	if(!above_turf)
		to_chat(src, "<span class='warning'>There's nowhere to go in that direction!</span>")
		return

	if(ismovable(loc)) //Inside an object, tell it we moved
		var/atom/loc_atom = loc
		return loc_atom.relaymove(src, UP)

	var/ventcrawling_flag = HAS_TRAIT(src, TRAIT_MOVE_VENTCRAWLING) ? ZMOVE_VENTCRAWLING : NONE
	if(can_z_move(DOWN, above_turf, current_turf, ZMOVE_FALL_FLAGS|ventcrawling_flag)) //Will we fall down if we go up?
		if(buckled)
			to_chat(src, "<span class='notice'>[buckled] is is not capable of flight.<span>")
		else
			to_chat(src, "<span class='notice'>You are not Superman.<span>")
		return
	if(zMove(UP, z_move_flags = ZMOVE_FLIGHT_FLAGS|ZMOVE_FEEDBACK|ventcrawling_flag))
		to_chat(src, span_notice("You move upwards."))

/mob/verb/move_down()
	set name = "Move Down"
	set category = "IC"

	if(remote_control)
		return remote_control.relaymove(src, DOWN)

	var/turf/current_turf = get_turf(src)
	var/turf/below_turf = GET_TURF_BELOW(current_turf)

	if(!below_turf)
		to_chat(src, span_warning("There's nowhere to go in that direction!"))
		return

	if(ismovable(loc)) //Inside an object, tell it we moved
		var/atom/loc_atom = loc
		return loc_atom.relaymove(src, DOWN)

	var/ventcrawling_flag = HAS_TRAIT(src, TRAIT_MOVE_VENTCRAWLING) ? ZMOVE_VENTCRAWLING : NONE
	if(zMove(DOWN, z_move_flags = ZMOVE_FLIGHT_FLAGS|ZMOVE_FEEDBACK|ventcrawling_flag))
		to_chat(src, span_notice("You move down."))
	return FALSE
