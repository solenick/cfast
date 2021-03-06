module spreadsheet_input_routines
    
    use precision_parameters

    use fire_routines, only: flame_height
    use utility_routines, only: upperall, set_heat_of_combustion, countargs

    use cfast_types, only: detector_type, fire_type, ramp_type, room_type, target_type, thermal_type, vent_type, visual_type
    
    use cparams, only: mxdtect, mxfires, mxhvents, mxvvents, mxramps, mxrooms, mxtarg, mxmvents, mxtabls, mxtablcols, &
        mxthrmp, mx_hsep, default_grid, pde, cylpde, smoked, heatd, sprinkd, trigger_by_time, trigger_by_temp, &
        trigger_by_flux, w_from_room, w_to_room, w_from_wall, w_to_wall
    use fire_data, only: n_fires, fireinfo, n_furn, furn_time, furn_temp, tgignt, lower_o2_limit, mxpts
    use ramp_data, only: n_ramps, rampinfo
    use room_data, only: nr, nrm1, roominfo, exterior_ambient_temperature, interior_ambient_temperature, exterior_abs_pressure, &
        interior_abs_pressure, pressure_ref, pressure_offset, exterior_rho, interior_rho, n_vcons, vertical_connections, &
        relative_humidity, adiabatic_walls
    use setup_data, only: iofili, iofill, rarray, carray, nrow, ncol, cfast_version, heading, title, time_end, &
        print_out_interval, smv_out_interval, ss_out_interval
    use solver_data, only: stpmax, stpmin, stpmin_cnt_max, stpminflag
    use smkview_data, only: n_visual, visualinfo
    use target_data, only: n_targets, targetinfo, n_detectors, detectorinfo
    use thermal_data, only: n_thrmp, thermalinfo
    use vent_data, only: n_hvents, hventinfo, n_vvents, vventinfo, n_mvents, mventinfo

    implicit none

    logical :: exset = .false.

    private

    public spreadsheet_input

    contains
    
     ! --------------------------- spreadsheet_input ----------------------------------
    subroutine spreadsheet_input
    
     implicit none

    integer :: numr, numc
    integer :: ivers, iversion
    character :: aversion*5
      
        ! read in the entire input file as a spreadsheet array of numbers and/or character strings
        call readcsvformat (iofili, rarray, carray, nrow, ncol, 1, numr, numc, iofill)
        close (iofili)
    
        ! aversion is the header name, ivers is the major version number read in, iversion is the major version number
        ! from the internal version data. these need to be compatible
        aversion = carray(1,1)
        ivers = rarray(1,2)
        ! new version numbering 600->6000, so current version is 7000
        if (cfast_version>=1000) then
            iversion = cfast_version/1000
        else
            iversion = cfast_version/100
        end if
    
        if (aversion==heading.and.ivers==iversion-1) then
            write (*,5004) ivers, iversion
            write (iofill,5004) ivers, iversion
        else if (aversion/=heading.or.ivers/=iversion) then
            write (*,5002) aversion,heading,ivers,iversion
            write (iofill,5002) aversion,heading,ivers,iversion
            stop
        end if
        title = carray(1,3)
        
        ! read in data file
        call keywordcases (numr, numc)

        return

5002 format ('***Error: Not a compatible version ',2a8,2x,2i10)
5004 format ('Opening a version ',i2,' file with version ',i2,'. Fire inputs may need to be updated.')
        
    end subroutine spreadsheet_input

    
    ! --------------------------- keywordcases -------------------------------------------

    subroutine keywordcases(inumr,inumc)

    !     routine:  keywordcases (remaned from NPUTQ)
    !     purpose: Handles CFAST datafile keywords
    !     Arguments: inumr    number of rows in input file spreadsheet
    !                inumc    number of columns in input file spreadsheet

    integer, parameter :: maxin = 37

    integer, intent(in) :: inumr, inumc

    integer :: i1, i2, fannumber, i, j, k, ir, icarea, icshape, icfraction
    integer :: iijk, jmax, npts, nto, ifrom, ito, imin, iroom, iramp, ncomp
    real(eb) :: initialopening, lrarray(ncol)
    real(eb) :: frac, tmpcond
    character :: label*5, tcname*64, eqtype*3, venttype
    character(128) :: lcarray(ncol)
    type(room_type), pointer :: roomptr
    type(target_type), pointer :: targptr
    type(detector_type), pointer :: dtectptr
    type(ramp_type), pointer :: rampptr
    type(visual_type), pointer :: sliceptr
    type(thermal_type), pointer :: thrmpptr
    type(fire_type), pointer :: fireptr
    type(vent_type), pointer :: ventptr

    ncomp = 0

    ! First check for a maximum time step. This may be modified by fires, vents, or detectors
    do ir = 2, inumr
        label = carray(ir,1)
        if (label==' ') cycle
        lrarray = 0.0_eb
        lcarray = ' '
        do i = 2, inumc
            lcarray(i-1) = carray(ir,i)
            lrarray(i-1) = rarray(ir,i)
        end do
        if (label=='STPMA') then
            if (countargs(lcarray)>=1) then
                stpmax = lrarray(1)
            else
                write (*,*) '***Error: Bad STPMA input. At least 1 argument required.'
                write (iofill,*) '***Error: Bad STPMA input. At least 1 argument required.'
                stop
            end if
        end if
    end do

    ! Then do thermal properties
    do ir = 2, inumr
        label = carray(ir,1)
        if (label==' ') cycle
        lrarray = 0.0_eb
        lcarray = ' '
        do i = 2, inumc
            lcarray(i-1) = carray(ir,i)
            lrarray(i-1) = rarray(ir,i)
        end do

        if (label=='MATL') then
            if (countargs(lcarray)>=7) then
                n_thrmp = n_thrmp + 1
                if (n_thrmp>mxthrmp) then
                    write (*,'(a,i3)') '***Error: Bad MATL input. Too many thermal properties in input data file. Limit is ', &
                        mxthrmp
                    write (iofill,'(a,i3)') '***Error: Bad MATL input. Too many thermal properties in input data file. Limit is ', &
                        mxthrmp
                    stop
                end if
                thrmpptr => thermalinfo(n_thrmp)
                thrmpptr%name = lcarray(1)
                thrmpptr%nslab = 1
                thrmpptr%k(1) = lrarray(2)
                thrmpptr%c(1) = lrarray(3)
                thrmpptr%rho(1) = lrarray(4)
                thrmpptr%thickness(1) = lrarray(5)
                thrmpptr%eps = lrarray(6)
            else
                write (*,*) '***Error: Bad MATL input. At least 7 arguments required.'
                write (iofill,*) '***Error: Bad MATL input. At least 7 arguments required.'
                stop
            end if
        end if
    end do

    ! Then do compartments
    do ir = 2, inumr
        label = carray(ir,1)
        if (label==' ') cycle
        lrarray = 0.0_eb
        lcarray = ' '
        do i = 2, inumc
            lcarray(i-1) = carray(ir,i)
            lrarray(i-1) = rarray(ir,i)
        end do

        ! COMPA	name(c), width(f), depth(f), height(f), absolute position (f) (3), ceiling_material(c),
        ! floor_material(c), wall_material (c)
        if (label=='COMPA') then
            if (countargs(lcarray)>=10) then

                ncomp = ncomp + 1
                if (ncomp>mxrooms) then
                    write (*, 5062) ncomp
                    write (iofill, 5062) ncomp
                    stop
                end if

                roomptr => roominfo(ncomp)
                ! Name
                roomptr%name = lcarray(1)

                ! Size
                roomptr%cwidth = lrarray(2)
                roomptr%cdepth = lrarray(3)
                roomptr%cheight = lrarray(4)
                roomptr%x0 = lrarray(5)
                roomptr%y0 = lrarray(6)
                roomptr%z0 = lrarray(7)

                ! Ceiling
                tcname = lcarray(8)
                if (tcname/='OFF') then
                    roomptr%surface_on(1) = .true.
                    roomptr%matl(1) = tcname
                end if

                ! floor
                tcname = lcarray(9)
                if (tcname/='OFF') then
                    roomptr%surface_on(2) = .true.
                    roomptr%matl(2) = tcname
                end if

                ! walls
                tcname = lcarray(10)
                if (tcname/='OFF') then
                    roomptr%surface_on(3) = .true.
                    roomptr%matl(3) = tcname
                    roomptr%surface_on(4) = .true.
                    roomptr%matl(4) = tcname
                end if

                ! If there are more than 10 arguments, it's the new format that includes grid spacing
                if (countargs(lcarray)==13) then
                    roomptr%ibar = lrarray(11)
                    roomptr%jbar = lrarray(12)
                    roomptr%kbar = lrarray(13)
                end if

                ! Reset this each time in case this is the last entry
                nr = ncomp + 1
            else
                write (*,*) '***Error: Bad COMPA input. At least 10 arguments required.'
                write (iofill,*) '***Error: Bad COMPA input. At least 10 arguments required.'
                stop
            end if
        end if
    end do

    ! Then do targets
    do ir = 2, inumr
        label = carray(ir,1)
        if (label==' ') cycle
        lrarray = 0.0_eb
        lcarray = ' '
        do i = 2, inumc
            lcarray(i-1) = carray(ir,i)
            lrarray(i-1) = rarray(ir,i)
        end do

        !	TARGET - Compartment position(3) normal(3) Material Method Equation_Type
        if (label=='TARGE') then
            if (countargs(lcarray)>=10) then
                if (n_targets+1>mxtarg) then
                    write (*,5002)
                    write (iofill,5002)
                    stop
                end if

                ! The target can exist, now for the compartment
                n_targets = n_targets + 1
                iroom = lrarray(1)
                if (iroom<1.or.iroom>nr) then
                    write (*,5003) iroom
                    write (iofill,5003) iroom
                    stop
                end if
                targptr => targetinfo(n_targets)
                targptr%room = iroom

                ! position and normal vector
                targptr%center(1:3) = lrarray(2:4)
                targptr%normal(1:3) = lrarray(5:7)

                if (countargs(lcarray)>=11) then
                    targptr%depth_loc = lrarray(11)
                else
                    targptr%depth_loc = 0.5
                end if

                ! target name
                if (countargs(lcarray)>=12) then
                    targptr%name = lcarray(12)
                else
                    write (targptr%name,'(a5,i0)') 'Targ ', n_targets
                end if

                ! material type
                tcname = lcarray(8)
                if (tcname==' ') tcname='DEFAULT'
                targptr%material = tcname
                targptr%wall = 0

                ! equation type, PDE or CYL.  ODE is outdated and changed to PDE if it's in an input file.
                eqtype = ' '
                eqtype = lcarray(10)
                call upperall(eqtype)
                if (eqtype/=' ') then
                    if (eqtype(1:3)=='ODE') then
                        targptr%equaton_type = pde
                        write (*,913) 'Warning', eqtype
                        write (iofill,913) 'Warning', eqtype
                    else if (eqtype(1:3)=='PDE') then
                        targptr%equaton_type = pde
                    else if (eqtype(1:3)=='CYL') then
                        targptr%equaton_type = cylpde
                    else
                        write (*,913) 'Error',eqtype
                        write (iofill,913) 'Error',eqtype
                        stop
                    end if
                end if
            else
                write (*,*) '***Error: Bad TARGE input. At least 10 arguments required.'
                write (iofill,*) '***Error: Bad TARGE input. At least 10 arguments required.'
                stop
            end if
        end if
    end do

    ! Then do fires
    do ir = 2, inumr
        label = carray(ir,1)
        if (label==' ') cycle
        lrarray = 0.0_eb
        lcarray = ' '
        do i = 2, inumc
            lcarray(i-1) = carray(ir,i)
            lrarray(i-1) = rarray(ir,i)
        end do

        ! FIRE room pos(3) plume ignition_type ignition_criterion normal(3) name
        ! This is almost the same as the older OBJEC keyword (name is moved to the end to make it more
        ! consistent with other keywords
        ! With the FIRE keyword, the rest of the fire definition follows in CHEMI, TIME, HRR, SOOT, CO, and TRACE keywords
        ! For now, we assume that the input file was written correctly by the GUI and just set an index for the forthcoming keywords
        if (label=='FIRE') then
            if (countargs(lcarray)/=11) then
                write (*,*) '***Error: Bad FIRE input. 11 arguments required.'
                write (iofill,*) '***Error: Bad FIRE input. 11 arguments required.'
                stop
            end if
            if (n_fires>=mxfires) then
                write (*,5300)
                write (iofill,5300)
                stop
            end if
            iroom = lrarray(1)
            if (iroom<1.or.iroom>nr-1) then
                write (*,5320) iroom
                write (iofill,5320) iroom
                stop
            end if
            roomptr => roominfo(iroom)
            n_fires = n_fires + 1
            fireptr => fireinfo(n_fires)

            ! Only constrained fires
            fireptr%chemistry_type = 2
            if (fireptr%chemistry_type>2) then
                write (*,5321) fireptr%chemistry_type
                write (iofill,5321) fireptr%chemistry_type
                stop
            end if

            fireptr%x_position = lrarray(2)
            fireptr%y_position = lrarray(3)
            fireptr%z_position = lrarray(4)
            if (fireptr%x_position>roomptr%cwidth.or.fireptr%y_position>roomptr%cdepth.or.fireptr%z_position>roomptr%cheight) then
                write (*,5323) n_fires
                write (iofill,5323) n_fires
                stop
            end if
            fireptr%modified_plume = 1
            if (min(fireptr%x_position,roomptr%cwidth-fireptr%x_position)<=mx_hsep .or. &
                min(fireptr%y_position,roomptr%cdepth-fireptr%y_position)<=mx_hsep) fireptr%modified_plume = 2
            if (min(fireptr%x_position,roomptr%cwidth-fireptr%x_position)<=mx_hsep .and. &
                min(fireptr%y_position,roomptr%cdepth-fireptr%y_position)<=mx_hsep) fireptr%modified_plume = 3

            if (lcarray(6)=='TIME' .or. lcarray(6)=='TEMP' .or. lcarray(6)=='FLUX') then
                ! it's a new format fire line that point to an existing target rather than to one created for the fire
                if (lcarray(6)=='TIME') fireptr%ignition_type = trigger_by_time
                if (lcarray(6)=='TEMP') fireptr%ignition_type = trigger_by_temp
                if (lcarray(6)=='FLUX') fireptr%ignition_type = trigger_by_flux
                tmpcond = lrarray(7)
                fireptr%ignition_target = 0
                if (lcarray(6)=='TEMP' .or. lcarray(6)=='FLUX') then
                    do i = 1,n_targets
                        targptr => targetinfo(i)
                        if (targptr%name==lcarray(8)) fireptr%ignition_target = i
                    end do
                    if (fireptr%ignition_target==0) then
                        write (*,5324) n_fires
                        write (iofill,5324) n_fires
                        stop
                    end if
                end if
            else
                write (*,5322)
                write (iofill,5322)
                stop
            end if
            fireptr%room = iroom
            fireptr%name = lcarray(11)
            ! Note that ignition type 1 is time, type 2 is temperature and 3 is flux
            if (tmpcond>0.0_eb) then
                fireptr%ignited = .false.
                if (fireptr%ignition_type==trigger_by_time) then
                    fireptr%ignition_time = tmpcond
                    fireptr%ignition_criterion = 1.0e30_eb
                else if (fireptr%ignition_type==trigger_by_temp.or.fireptr%ignition_type==trigger_by_flux) then
                    fireptr%ignition_time = 1.0e30_eb
                    fireptr%ignition_criterion = tmpcond
                    if (stpmax>0) then
                        stpmax = min(stpmax,1.0_eb)
                    else
                        stpmax = 1.0_eb
                    end if
                else
                    write (*,5358) fireptr%ignition_type
                    write (iofill,5358) fireptr%ignition_type
                    stop
                end if
            else
                fireptr%ignited = .true.
                fireptr%reported = .true.
            end if

            ! read and set the other stuff for this fire
            call inputembeddedfire (fireptr, ir, inumc)
        end if
    end do

    ! Then do everything else
    do ir = 2, inumr

        label = carray(ir,1)
        if (label==' ') cycle
        lrarray = 0.0_eb
        lcarray = ' '
        do i = 2, inumc
            lcarray(i-1) = carray(ir,i)
            lrarray(i-1) = rarray(ir,i)
        end do

        !	Start the case statement for key words

        select case (label)

            ! TIMES total_simulation, print interval, smokeview interval, spreadsheet interval
        case ("TIMES")
            if (countargs(lcarray)>=5) then
                time_end =  lrarray(1)
                print_out_interval = abs(lrarray(2))
                smv_out_interval = lrarray(4)
                ss_out_interval =  lrarray(5)
            else if (countargs(lcarray)>=4) then
                time_end =  lrarray(1)
                print_out_interval = abs(lrarray(2))
                smv_out_interval = lrarray(3)
                ss_out_interval =  lrarray(4)
            else
                write (*,*) '***Error: Bad TIMES input. At least 4 arguments required.'
                write (iofill,*) '***Error: Bad TIMES input. At least 4 arguments required.'
                stop
            end if

            ! TAMB reference ambient temperature (c), reference ambient pressure, reference pressure, relative humidity
        case ("TAMB")
            if (countargs(lcarray)>=4) then
                interior_ambient_temperature = lrarray(1)
                relative_humidity = lrarray(4)*0.01_eb
            else if (countargs(lcarray)>=3) then
                interior_ambient_temperature = lrarray(1)
                relative_humidity = lrarray(3)*0.01_eb
            else
                write (*,*) '***Error: Bad TAMB input. At least 3 arguments required.'
                write (iofill,*) '***Error: Bad TAMB input. At least 3 arguments required.'
                stop
            end if
            if (.not.exset) then
                exterior_ambient_temperature = interior_ambient_temperature
                exterior_abs_pressure = interior_abs_pressure
                exterior_rho = interior_rho
            end if
            tgignt = interior_ambient_temperature + 200.0_eb

            ! EAMB reference external ambient temperature (c), reference external ambient pressure
        case ("EAMB")
            if (countargs(lcarray)/=3) then
                write (*,*) '***Error: Bad EAMB input. 3 arguments required.'
                write (iofill,*) '***Error: Bad EAMB input. 3 arguments required.'
                stop
            end if
            exterior_ambient_temperature = lrarray(1)
            exterior_abs_pressure = lrarray(2)
            exset = .true.
            
            ! LIMO2 lower oxygen limit for combustion. This is a global value
        case ("LIMO2")
            if (countargs(lcarray)/=1) then
                write (*,*) '***Error: Bad LIMO2 input. Only 1 argument allowed.'
                write (iofill,*) '***Error: Bad LIMO2 input. Only 1 argument allowed.'
                stop
            end if
            lower_o2_limit = lrarray(1)

            ! HVENT 1st, 2nd, which_vent, width, soffit, sill, wind_coef, hall_1, hall_2, face, opening_fraction,
            !           width, soffit, sill
            !		    absolute height of the soffit, absolute height of the sill,
            !           floor_height = absolute height of the floor (not set here)
            !		    compartment offset for the hall command (2 of these)
            !		    face = the relative face of the vent: 1-4 for x plane (-), y plane (+), x plane (+), y plane (-)
            !		    initial open fraction
        case ('HVENT')
            if (countargs(lcarray)<7) then
                write (*,*) '***Error: Bad HVENT input. At least 7 arguments required.'
                write (iofill,*) '***Error: Bad HVENT input. At least 7 arguments required.'
                stop
            else
                i = lrarray(1)
                j = lrarray(2)
                k = lrarray(3)
                imin = min(i,j)
                jmax = max(i,j)
                if (imin>mxrooms-1.or.jmax>mxrooms.or.imin==jmax) then
                    write (*,5070) i, j
                    write (iofill,5070) i, j
                    stop
                end if

                n_hvents = n_hvents + 1
                ventptr => hventinfo(n_hvents)
                ventptr%room1 = imin
                ventptr%room2 = jmax
                ventptr%counter = lrarray(3)

                if (n_hvents>mxhvents) then
                    write (*,5081) i,j,k
                    write (iofill,5081) i,j,k
                    stop
                end if

                ventptr%width = lrarray(4)
                ventptr%soffit = lrarray(5)
                ventptr%sill = lrarray(6)
            end if
            if (lcarray(10)=='TIME' .or. lcarray(10)=='TEMP' .or. lcarray(10)=='FLUX') then
                ventptr%offset(1) = lrarray(7)
                ventptr%offset(2) = 0.0_eb
                ventptr%face = lrarray(9)
                if (lcarray(10)=='TIME') then
                    ventptr%opening_type = trigger_by_time
                    ventptr%opening_initial_time = lrarray(13)
                    ventptr%opening_initial_fraction = lrarray(14)
                    ventptr%opening_final_time = lrarray(15)
                    ventptr%opening_final_fraction = lrarray(16)
                else
                    if (lcarray(10)=='TEMP') ventptr%opening_type = trigger_by_temp
                    if (lcarray(10)=='FLUX') ventptr%opening_type = trigger_by_flux
                    ventptr%opening_criterion = lrarray(11)
                    ventptr%opening_target = 0
                    do i = 1,n_targets
                        targptr => targetinfo(i)
                        if (targptr%name==lcarray(12)) ventptr%opening_target = i
                    end do
                    if (ventptr%opening_target==0) then
                        write (*,*) '***Error: Bad HVENT input. Vent opening specification requires an associated target.'
                        write (iofill,*) '***Error: Bad HVENT input. Vent opening specification requires an associated target.'
                        stop
                    end if   
                    ventptr%opening_initial_fraction = lrarray(14)
                    ventptr%opening_final_fraction = lrarray(16)
                    if (stpmax>0) then
                        stpmax = min(stpmax,1.0_eb)
                    else
                        stpmax = 1.0_eb
                    end if
                end if
            else if (countargs(lcarray)>=11) then
                ventptr%offset(1) = lrarray(8)
                ventptr%offset(2) = lrarray(9)
                ventptr%face = lrarray(10)
                initialopening = lrarray(11)
                ventptr%opening_type = trigger_by_time
                ventptr%opening_initial_fraction = initialopening
                ventptr%opening_final_fraction = initialopening
            else if (countargs(lcarray)>=9) then
                ventptr%offset(1) = lrarray(7)
                ventptr%offset(2) = 0.0_eb
                ventptr%opening_type = trigger_by_time
                ventptr%face = lrarray(8)
                initialopening = lrarray(9)
                ventptr%opening_initial_fraction = initialopening
                ventptr%opening_final_fraction = initialopening
            else
                write (*,*) '***Error: Bad HVENT input. At least 7 arguments required.'
                write (iofill,*) '***Error: Bad HVENT input. At least 7 arguments required.'
                stop
            end if
            roomptr => roominfo(ventptr%room1)
            ventptr%absolute_soffit = ventptr%soffit + roomptr%z0
            ventptr%absolute_sill = ventptr%sill + roomptr%z0

            ! DEADROOM dead_room_num connected_room_num
            ! pressure in dead_room_num is not solved.  pressure for this room
            ! is obtained from connected_room_num
        case ('DEADR')
            i = lrarray(1)
            j = lrarray(2)
            if (i.ge.1.and.i.le.mxrooms.and.j.le.1.and.j.le.mxrooms.and.i.ne.j) then
                roomptr => roominfo(i)
                roomptr%deadroom = j
            end if

            ! EVENT keyword, the four possible formats are:
            ! EVENT   H     First_Compartment   Second_Compartment	 Vent_Number    Time   Final_Fraction   decay_time
            ! EVENT   V     First_Compartment   Second_Compartment	 Not_Used	    Time   Final_Fraction   decay_time
            ! EVENT   M        Not_Used             Not_used            M_ID        Time   Final_Fraction   decay_time
            ! EVENT   F        Not_Used             Not_used            M_ID        Time   Final_Fraction   decay_time
        case ('EVENT')
            if (countargs(lcarray)>=7) then
                !	        Sort by event type, h, v, m, or f
                venttype = lcarray(1)

                if (lrarray(6)<0.0_eb.or.lrarray(6)>1.0_eb) then
                    write (*,*) '****Error: Bad EVENT input. Final_Fraction (6th argument) must be between 0 and 1 inclusive.'
                    write (iofill,*) '****Error: Bad EVENT input. Final_Fraction (6th argument) must be between 0 and 1 inclusive.'
                    stop
                end if

                select case (venttype)
                case ('H')
                    i = lrarray(2)
                    j = lrarray(3)
                    k = lrarray(4)
                    do iijk = 1, n_hvents
                        ventptr => hventinfo(iijk)
                        if (ventptr%room1==i.and.ventptr%room2==j.and.ventptr%counter==k) then
                            ventptr%opening_initial_time = lrarray(5)
                            ventptr%opening_final_time = lrarray(5) + lrarray(7)
                            ventptr%opening_final_fraction = lrarray(6)
                        end if
                    end do
                case ('V')
                    i = lrarray(2)
                    j = lrarray(3)
                    k = lrarray(4)
                    do iijk = 1, n_vvents
                        ventptr => vventinfo(iijk)
                        if (ventptr%room1==i.and.ventptr%room2==j.and.ventptr%counter==k) then
                            ventptr%opening_initial_time = lrarray(5)
                            ventptr%opening_final_time = lrarray(5) + lrarray(7)
                            ventptr%opening_final_fraction = lrarray(6)
                        end if
                    end do
                case ('M')
                    i = lrarray(2)
                    j = lrarray(3)
                    k = lrarray(4)
                    do iijk = 1, n_mvents
                        ventptr => mventinfo(iijk)
                        if (ventptr%room1==i.and.ventptr%room2==j.and.ventptr%counter==k) then
                            ventptr%opening_initial_time = lrarray(5)
                            ventptr%opening_final_time = lrarray(5) + lrarray(7)
                            ventptr%opening_final_fraction = lrarray(6)
                        end if
                    end do
                case ('F')
                    i = lrarray(2)
                    j = lrarray(3)
                    fannumber = lrarray(4)
                    if (fannumber>n_mvents) then
                        write (*,5196) fannumber
                        write (iofill,5196) fannumber
                        stop
                    end if
                    ventptr => mventinfo(fannumber)
                    ventptr%filter_initial_time = lrarray(5)
                    ventptr%filter_final_time = lrarray(5) + lrarray(7)
                    ventptr%filter_final_fraction = lrarray(6)
                    case default
                    write (*,*) '***Error: Bad EVENT input. Type (1st arguement) must be H, V, M, or F.'
                    write (iofill,*) '***Error: Bad EVENT input. Type (1st arguement) must be H, V, M, or F.'
                    stop
                end select
            else
                write (*,*) '***Error: Bad EVENT input. At least 7 arguments required.'
                write (iofill,*) '***Error: Bad EVENT input. At least 7 arguments required.'
                stop
            end if

            ! RAMP - from_compartment (or 0) to_compartment (or 0) vent_or_fire_number number_of_xy_pairs x1 y1 x2 y2 ... xn yn
        case ('RAMP')
            if (countargs(lcarray)<9) then
                write (*,*) '***Error: Bad RAMP input. At least 9 arguments required.'
                write (iofill,*) '***Error: Bad RAMP input. At least 9 arguments required.'
                stop
            else if (lrarray(5)<=1) then
                write (*,*) '***Error: Bad RAMP input. At least 1 time point must be specified.'
                write (iofill,*) '***Error: Bad RAMP input. At least 1 time point must be specified.'
                stop
            else if (countargs(lcarray)/=5+2*lrarray(5)) then
                write (*,*) '***Error: Bad RAMP input. Inputs must be in pairs.'
                write (iofill,*) '***Error: Bad RAMP input. Inputs must be in pairs.'
                stop
            end if
            if (n_ramps<=mxramps) then
                n_ramps = n_ramps + 1
                rampptr=>rampinfo(n_ramps)
                rampptr%type = lcarray(1)
                rampptr%room1 = lrarray(2)
                rampptr%room2 = lrarray(3)
                rampptr%counter = lrarray(4)
                rampptr%npoints = lrarray(5)
                do iramp = 1,rampptr%npoints
                    rampptr%x(iramp) = lrarray(4+2*iramp)
                    rampptr%f_of_x(iramp) = lrarray(5+2*iramp)
                end do
            end if

            ! VVENT - from_compartment to_compartment area shape initial_fraction
        case ('VVENT')
            if (countargs(lcarray)>=5) then
                i = lrarray(1)
                j = lrarray(2)
                if (countargs(lcarray)==5) then
                    ! oldest format that only allows one vent per compartment pair
                    k = 1
                    icarea = 3
                    icshape = 4
                    icfraction = 5
                else
                    ! newer format that allows more than one vent per compartment pair
                    k = lrarray(3)
                    icarea = 4
                    icshape = 5
                    icfraction = 6
                end if
                ! check for outside of compartment space; self pointers are covered in read_input_file
                if (i>mxrooms.or.j>mxrooms) then
                    write (iofill,5070) i, j
                    write (iofill,5070) i, j
                    stop
                end if
                n_vvents = n_vvents + 1
                ventptr => vventinfo(n_vvents)
                ventptr%room1 = i
                ventptr%room2 = j
                ventptr%counter = k
                ! read_input_file will verify the orientation (i is on top of j)
                ventptr%area = lrarray(icarea)
                ! check the shape parameter. the default (1) is a circle)
                if (lrarray(icshape)<1.or.lrarray(icshape)>2) then
                    ventptr%shape = 1
                else
                    ventptr%shape = lrarray(icshape)
                end if
                if (lcarray(6)=='TIME' .or. lcarray(6)=='TEMP' .or. lcarray(6)=='FLUX') then
                    if (lcarray(6)=='TIME') then
                        ventptr%opening_type = trigger_by_time
                        ventptr%opening_initial_time = lrarray(9)
                        ventptr%opening_initial_fraction = lrarray(10)
                        ventptr%opening_final_time = lrarray(11)
                        ventptr%opening_final_fraction = lrarray(12)
                    else
                        if (lcarray(6)=='TEMP') ventptr%opening_type = trigger_by_temp
                        if (lcarray(6)=='FLUX') ventptr%opening_type = trigger_by_flux
                        ventptr%opening_criterion = lrarray(7)
                        ventptr%opening_target = 0
                        do i = 1,n_targets
                            targptr => targetinfo(i)
                            if (targptr%name==lcarray(8)) ventptr%opening_target = i
                        end do
                        if (ventptr%opening_target==0) then
                            write (*,*) '***Error: Bad HVENT input. Vent opening specification requires an associated target.'
                            write (iofill,*) '***Error: Bad HVENT input. Vent opening specification requires an associated target.'
                            stop
                        end if  
                        ventptr%opening_initial_fraction = lrarray(10)
                        ventptr%opening_final_fraction = lrarray(12)
                        if (stpmax>0) then
                            stpmax = min(stpmax,1.0_eb)
                        else
                            stpmax = 1.0_eb
                        end if
                    end if
                    ventptr%xoffset = lrarray(13)
                    ventptr%yoffset = lrarray(14)
                else
                    ventptr%opening_type = trigger_by_time
                    ventptr%opening_initial_fraction = lrarray(icfraction)
                    ventptr%opening_final_fraction = lrarray(icfraction)
                    if (ventptr%room1<=nr-1) then
                        roomptr => roominfo(ventptr%room1)
                        ventptr%xoffset = roomptr%cwidth/2
                        ventptr%yoffset = roomptr%cdepth/2
                    else
                        roomptr => roominfo(ventptr%room2)
                        ventptr%xoffset = roomptr%cwidth/2
                        ventptr%yoffset = roomptr%cdepth/2
                    end if

                end if
            else
                write (*,*) '***Error: Bad VVENT input. At least 5 arguments required.'
                write (iofill,*) '***Error: Bad VVENT input. At least 5 arguments required.'
                stop
            end if

            ! MVENT - simplified mechanical ventilation

            ! (1) From_Compartment, (2) To_Compartment, (3) ID_Number
            ! (4-6) From_Opening_Orientation From_Center_Height From_Opening_Area
            ! (7-9) To_Opening_Orientation To_Center_Height To_Opening_Area
            ! (10-12) Flow Flow_Begin_Dropoff_Pressure Zero_Flow_Pressure
            ! (13) Initial fraction of the fan speed
        case ('MVENT')
            if (countargs(lcarray)>=13) then
                i = lrarray(1)
                j = lrarray(2)
                k = lrarray(3)
                if (i>nr.or.j>nr) then
                    write (*,5191) i, j
                    write (iofill,5191) i, j
                    stop
                end if
                n_mvents = n_mvents + 1
                ventptr => mventinfo(n_mvents)
                ventptr%room1 = i
                ventptr%room2 = j
                ventptr%counter = k

                if (lcarray(4)=='V') then
                    ventptr%orientation(1) = 1
                else
                    ventptr%orientation(1) = 2
                end if
                ventptr%height(1) = lrarray(5)
                ventptr%diffuser_area(1) = lrarray(6)

                if (lcarray(7)=='V') then
                    ventptr%orientation(2) = 1
                else
                    ventptr%orientation(2) = 2
                end if
                ventptr%height(2) = lrarray(8)
                ventptr%diffuser_area(2) = lrarray(9)

                ventptr%n_coeffs = 1
                ventptr%coeff = 0.0_eb
                ventptr%coeff(1) = lrarray(10)
                ventptr%maxflow = lrarray(10)
                ventptr%min_cutoff_relp = lrarray(11)
                ventptr%max_cutoff_relp = lrarray(12)

                if (lcarray(13)=='TIME' .or. lcarray(13)=='TEMP' .or. lcarray(13)=='FLUX') then
                    if (lcarray(13)=='TIME') then
                        ventptr%opening_type = trigger_by_time
                        ventptr%opening_initial_time = lrarray(16)
                        ventptr%opening_initial_fraction = lrarray(17)
                        ventptr%opening_final_time = lrarray(18)
                        ventptr%opening_final_fraction = lrarray(19)
                    else
                        if (lcarray(13)=='TEMP') ventptr%opening_type = trigger_by_temp
                        if (lcarray(13)=='FLUX') ventptr%opening_type = trigger_by_flux
                        ventptr%opening_criterion = lrarray(14)
                        ventptr%opening_target = 0
                        do i = 1,n_targets
                            targptr => targetinfo(i)
                            if (targptr%name==lcarray(15)) ventptr%opening_target = i
                        end do
                        if (ventptr%opening_target==0) then
                            write (*,*) '***Error: Bad HVENT input. Vent opening specification requires an associated target.'
                            write (iofill,*) '***Error: Bad HVENT input. Vent opening specification requires an associated target.'
                            stop
                        end if  
                        ventptr%opening_initial_fraction = lrarray(17)
                        ventptr%opening_final_fraction = lrarray(19)
                    end if
                    ventptr%xoffset = lrarray(20)
                    ventptr%yoffset = lrarray(21)
                    if (stpmax>0) then
                        stpmax = min(stpmax,1.0_eb)
                    else
                        stpmax = 1.0_eb
                    end if
                else
                    ventptr%opening_type = trigger_by_time
                    ventptr%opening_initial_fraction = lrarray(13)
                    ventptr%opening_final_fraction = lrarray(13)
                    if (ventptr%room1<=nr-1) then
                        roomptr => roominfo(ventptr%room1)
                        ventptr%xoffset = 0.0_eb
                        ventptr%yoffset = roomptr%cdepth/2
                    else
                        roomptr => roominfo(ventptr%room2)
                    end if
                    ventptr%xoffset = 0.0_eb
                    ventptr%yoffset = roomptr%cdepth/2
                end if
            else
                write (*,*) '***Error: Bad MVENT input. 13 arguments required.'
                write (iofill,*) '***Error: Bad MVENT input. 13 arguments required.'
                stop
            end if

            ! DETECT Type Compartment Activation_Value Width Depth Height RTI Suppression Spray_Density
        case ('DETEC')
            if (countargs(lcarray)>=9) then
                n_detectors = n_detectors + 1

                if (n_detectors>mxdtect) then
                    write (*, 5338)
                    write (iofill, 5338)
                    stop
                end if

                dtectptr => detectorinfo(n_detectors)
                if (lcarray(1)=='SMOKE') then
                    i1 = smoked
                else if (lcarray(1)=='HEAT') then
                    i1 = heatd
                else if (lcarray(1)=='SPRINKLER') then
                    i1 = sprinkd
                else
                    i1 = lrarray(1)
                    ! force to heat detector if out of range
                    if (i1>3) i1 = heatd
                end if
                dtectptr%dtype = i1

                i2 = lrarray(2)
                iroom = i2
                dtectptr%room = iroom
                if (iroom<1.or.iroom>mxrooms) then
                    write (*,5342) i2
                    write (iofill,5342) i2
                    stop
                end if

                dtectptr%trigger = lrarray(3)
                dtectptr%center(1) = lrarray(4)
                dtectptr%center(2) = lrarray(5)
                dtectptr%center(3) = lrarray(6)
                dtectptr%rti =  lrarray(7)
                if (lrarray(8)/=0) then
                    dtectptr%quench = .true.
                else
                    dtectptr%quench = .false.
                end if
                dtectptr%spray_density = lrarray(9)*1000.0_eb
                ! if spray density is zero, then turn off the sprinkler
                if (dtectptr%spray_density==0.0_eb) then
                    dtectptr%quench = .false.
                end if
                ! if there's a sprinkler that can go off, then make sure the time step is small enough to report it accurately
                if (dtectptr%quench) then
                    if (stpmax>0) then
                        stpmax = min(stpmax,1.0_eb)
                    else
                        stpmax = 1.0_eb
                    end if
                end if
                roomptr => roominfo(iroom)
                if (roomptr%name==' ') then
                    write (*,5344) i2
                    write (iofill,5344) i2
                    stop
                end if

                if (dtectptr%center(1)>roomptr%cwidth.or. &
                    dtectptr%center(2)>roomptr%cdepth.or.dtectptr%center(3)>roomptr%cheight) then
                write (*,5339) n_detectors,roomptr%name
                write (iofill,5339) n_detectors,roomptr%name
                stop
                end if

            else
                write (*,*) '***Error: Bad DETEC input. At least 9 arguments required.'
                write (iofill,*) '***Error: Bad DETEC input. At least 9 arguments required.'
                stop
            end if

            !  VHEAT top_compartment bottom_compartment
        case ('VHEAT')
            if (countargs(lcarray)>=2) then
                i1 = lrarray(1)
                i2 = lrarray(2)
                if (i1<1.or.i2<1.or.i1>nr.or.i2>nr) then
                    write (*,5345) i1, i2
                    write (iofill,5345) i1, i2
                    stop
                end if

                n_vcons = n_vcons + 1
                vertical_connections(n_vcons,w_from_room) = i1
                vertical_connections(n_vcons,w_from_wall) = 2
                vertical_connections(n_vcons,w_to_room) = i2
                vertical_connections(n_vcons,w_to_wall) = 1
            else
                write (*,*) '***Error: Bad VHEAT input. At least 2 arguments required.'
                write (iofill,*) '***Error: Bad VHEAT input. At least 2 arguments required.'
                stop
            end if

            ! ONEZ compartment number - This turns the compartment into a single zone
        case ('ONEZ')
            if (countargs(lcarray)>=1) then
                iroom = lrarray(1)
                if (iroom<1.or.iroom>nr) then
                    write (*, 5001) i1
                    write (iofill, 5001) i1
                    stop
                end if
                roomptr => roominfo(iroom)
                roomptr%shaft = .true.
            else
                write (*,*) '***Error: Bad ONEZ input. At least 1 compartment must be specified.'
                write (iofill,*) '***Error: Bad ONEZ input. At least 1 compartment must be specified.'
                stop
            end if

            ! HALL Compartment Velocity Depth Decay_Distance
        case ('HALL')
            if (countargs(lcarray)>=1) then
                iroom = lrarray(1)

                ! check that specified room is valid
                if (iroom<0.or.iroom>nr) then
                    write (*,5346) iroom
                    write (iofill,5346) iroom
                    stop
                end if

                roomptr => roominfo(iroom)
                roomptr%hall = .true.
                if (countargs(lcarray)>1) then
                    write (*,5406) iroom
                    write (iofill,5406) iroom
                end if
            else
                write (*,*) '***Error: Bad HALL input. At least 1 compartment must be specified.'
                write (iofill,*) '***Error: Bad HALL input. At least 1 compartment must be specified.'
                stop
            end if

            ! ROOMA Compartment Number_of_Area_Values Area_Values
            ! This provides for variable compartment floor areas; this should be accompanied by the roomh command
        case ('ROOMA')
            if (countargs(lcarray)>=2) then
                iroom = lrarray(1)
                roomptr => roominfo(iroom)

                ! make sure the room number is valid
                if (iroom<1.or.iroom>nr) then
                    write (*,5347) iroom
                    write (iofill,5347) iroom
                    stop
                end if

                ! make sure the number of points is valid
                npts = lrarray(2)
                if (npts>mxpts.or.npts<=0.or.npts/=countargs(lcarray)-2) then
                    write (*,5347) npts
                    write (iofill,5347) npts
                    stop
                end if
                if (roomptr%nvars/=0) npts = min(roomptr%nvars,npts)
                roomptr%nvars = npts

                ! make sure all data is positive
                do  i = 1, npts
                    if (lrarray(i+2)<0.0_eb) then
                        write (*,5348) lrarray(i+2)
                        write (iofill,5348) lrarray(i+2)
                        stop
                    end if
                end do

                ! put the data in its place
                do i = 1, npts
                    roomptr%var_area(i) = lrarray(i+2)
                end do
            else
                write (*,*) '***Error: Bad ROOMA input. At least 2 arguments must be specified.'
                write (iofill,*) '***Error: Bad ROOMA input. At least 2 arguments must be specified.'
                stop
            end if

            ! ROOMH Compartment Number_of_Height_Values Height_Values
            ! This companion to ROOMA, provides for variable compartment floor areas; this should be accompanied by the ROOMA command
        case ('ROOMH')
            if (countargs(lcarray)>=2) then
                iroom = lrarray(1)
                roomptr => roominfo(iroom)

                ! make sure the room number is valid
                if (iroom<1.or.iroom>nr) then
                    write (*,5349) iroom
                    write (iofill,5349) iroom
                    stop
                end if

                ! make sure the number of points is valid
                npts = lrarray(2)
                if (npts>mxpts.or.npts<0.or.npts/=countargs(lcarray)-2) then
                    write (*,5350) npts
                    write (iofill,5350) npts
                    stop
                end if
                if (roomptr%nvars/=0)npts = min(roomptr%nvars,npts)
                roomptr%nvars = npts

                ! make sure all data is positive
                do i = 1, npts
                    if (lrarray(i+2)<0.0_eb) then
                        write (*,5348) lrarray(i+2)
                        write (iofill,5348) lrarray(i+2)
                        stop
                    end if
                end do

                ! put the data in its place
                do i = 1, npts
                    roomptr%var_height(i) = lrarray(i+2)
                end do

            else
                write (*,*) '***Error: Bad ROOMH input. At least 2 arguments must be specified.'
                write (iofill,*) '***Error: Bad ROOMH input. At least 2 arguments must be specified.'
                stop
            end if

            ! DTCHE Minimum_Time_Step Maximum_Iteration_Count
        case ('DTCHE')
            if (countargs(lcarray)>=2) then
                stpmin = abs(lrarray(1))
                stpmin_cnt_max = abs(lrarray(2))
                ! a negative turns off the check
                if (lrarray(2)<=0) stpminflag = .false.
            else
                write (*,*) '***Error: Bad DTCHE input. At least 2 arguments must be specified.'
                write (iofill,*) '***Error: Bad DTCHE input. At least 2 arguments must be specified.'
                stop
            end if

            ! Horizontal heat flow, HHEAT First_Compartment Number_of_Parts nr pairs of {Second_Compartment, Fraction}

            ! There are two forms of the command
            !   The first (single entry of the room number) - all connections based on horizontal flow
            !   The second is the compartment number followed by nr pairs of compartments to which the heat
            !   will flow and the fraction of the vertical surface of the compartment that loses heat
        case ('HHEAT')
            if (countargs(lcarray)>=1) then
                nto = 0
                ifrom = lrarray(1)
                roomptr => roominfo(ifrom)
                if (countargs(lcarray)==1) then
                    roomptr%iheat = 1
                    cycle
                else
                    nto = lrarray(2)
                    if (nto<1.or.nto>nr) then
                        write (*,5354) nto
                        write (iofill,5354) nto
                        stop
                    end if
                    roomptr%iheat = 2
                end if

                if (2*nto==(countargs(lcarray)-2)) then
                    do i = 1, nto
                        i1 = 2*i+1
                        i2 = 2*i+2
                        ito = lrarray(i1)
                        frac = lrarray(i2)
                        if (ito<1.or.ito==ifrom.or.ito>nr) then
                            write (*, 5356) ifrom,ito
                            write (iofill, 5356) ifrom,ito
                            stop
                        end if
                        if (frac<0.0_eb.or.frac>1.0_eb) then
                            write (*, 5357) ifrom,ito,frac
                            write (iofill, 5357) ifrom,ito,frac
                            stop
                        end if
                        roomptr%heat_frac(ito) = frac
                    end do
                else
                    write (*,5355) ifrom, nto
                    write (iofill,5355) ifrom, nto
                    stop
                end if
            else
                write (*,*) '***Error: Bad HHEAT input. At least 1 arguments must be specified.'
                write (iofill,*) '***Error: Bad HHEAT input. At least 1 arguments must be specified.'
                stop
            end if

            ! FURN - no fire, heat walls according to a prescribed time temperature curve
        case ('FURN')
            n_furn=lrarray(1)+0.5
            do i = 1, n_furn
                furn_time(i)=lrarray(2*i)
                furn_temp(i)=lrarray(2*i+1)
            end do

            ! ADIAB - all surfaces are adiabatic so that dT/dx at the surface = 0
        case ('ADIAB')
            adiabatic_walls = .true.

            ! SLCF 2-D and 3-D slice files
        case ('SLCF')
            if (countargs(lcarray)>=1) then
                n_visual = n_visual + 1
                sliceptr => visualinfo(n_visual)
                if (lcarray(1)=='2-D') then
                    sliceptr%vtype = 1
                else if (lcarray(1)=='3-D') then
                    sliceptr%vtype = 2
                else
                    write (*, 5403) n_visual
                    write (iofill, 5403) n_visual
                    stop
                end if
                ! 2-D slice file
                if (sliceptr%vtype==1) then
                    ! get position (required) and compartment (optional) first so we can check to make sure
                    ! desired position is within the compartment(s)
                    if (countargs(lcarray)>2) then
                        sliceptr%position = lrarray(3)
                        if (countargs(lcarray)>3) then
                            sliceptr%roomnum = lrarray(4)
                        else
                            sliceptr%roomnum = 0
                        end if
                        if (sliceptr%roomnum<0.or.sliceptr%roomnum>nr-1) then
                            write (*, 5403) n_visual
                            write (iofill, 5403) n_visual
                            stop
                        end if
                        if (lcarray(2) =='X') then
                            sliceptr%axis = 1
                            if (sliceptr%roomnum>0) then
                                roomptr => roominfo(sliceptr%roomnum)
                                if (sliceptr%position>roomptr%cwidth.or.sliceptr%position<0.0_eb) then
                                    write (*, 5403) n_visual
                                    write (iofill, 5403) n_visual
                                    stop
                                end if
                            end if
                        else if (lcarray(2) =='Y') then
                            sliceptr%axis = 2
                            if (sliceptr%roomnum>0) then
                                roomptr => roominfo(sliceptr%roomnum)
                                if (sliceptr%position>roomptr%cdepth.or.sliceptr%position<0.0_eb) then
                                    write (*, 5403) n_visual
                                    write (iofill, 5403) n_visual
                                    stop
                                end if
                            end if
                        else if (lcarray(2) =='Z') then
                            sliceptr%axis = 3
                            if (sliceptr%roomnum>0) then
                                roomptr => roominfo(sliceptr%roomnum)
                                if (sliceptr%position>roomptr%cheight.or.sliceptr%position<0.0_eb) then
                                    write (*, 5403) n_visual
                                    write (iofill, 5403) n_visual
                                    stop
                                end if
                            end if
                        else
                            write (*, 5403) n_visual
                            write (iofill, 5403) n_visual
                            stop
                        end if
                    else
                        write (*, 5403) n_visual
                        write (iofill, 5403) n_visual
                        stop
                    end if
                    ! 3-D slice
                else if (sliceptr%vtype==2) then
                    if (countargs(lcarray)>1) then
                        sliceptr%roomnum = lrarray(2)
                    else
                        sliceptr%roomnum = 0
                    end if
                    if (sliceptr%roomnum<0.or.sliceptr%roomnum>nr-1) then
                        write (*, 5403) n_visual
                        write (iofill, 5403) n_visual
                        stop
                    end if
                end if
            else
                write (*,*) '***Error: Bad SLCF input. At least 1 arguments must be specified.'
                write (iofill,*) '***Error: Bad SLCF input. At least 1 arguments must be specified.'
                stop
            end if

            ! ISOF isosurface of specified temperature in one or all compartments
        case ('ISOF')
            if (countargs(lcarray)>=1) then
                n_visual = n_visual + 1
                sliceptr => visualinfo(n_visual)
                sliceptr%vtype = 3
                sliceptr%value = lrarray(1)
                if (countargs(lcarray)>1) then
                    sliceptr%roomnum = lrarray(2)
                else
                    sliceptr%roomnum = 0
                end if
                if (sliceptr%roomnum<0.or.sliceptr%roomnum>nr-1) then
                    write (*, 5404) n_visual
                    write (iofill, 5404) n_visual
                    stop
                end if
            else
                write (*,*) '***Error: Bad SLCF input. At least 1 arguments must be specified.'
                write (iofill,*) '***Error: Bad SLCF input. At least 1 arguments must be specified.'
                stop
            end if

            ! Outdated keywords
        case ('CJET','WIND','GLOBA','DJIGN') ! Just ignore these inputs ... they shouldn't be fatal
            write (*,5407) label
            write (iofill,5407) label
        case ('OBJFL','MVOPN','MVFAN','MAINF','INTER','SETP','THRMF','OBJEC') ! these are clearly outdated and produce errors
            write (*,5405) label
            write (iofill,5405) label
            stop
        case ('MATL','COMPA','TARGE','HEIGH','AREA','TRACE','CO','SOOT',&
            'HRR','TIME','CHEMI','FIRE','STPMA') ! these are already handled above

        case default
        write (*, 5051) label
        write (iofill, 5051) label
        stop
        end select
    end do

913 format('***',a,': BAD TARGE input. Invalid equation type:',A3,' Valid choices are: PDE or CYL')
5001 format ('***Error: Bad ONEZ input. Referenced compartment is not defined ',i0)
5002 format ('***Error: BAD TARGE input. Too many targets are being defined')
5003 format ('***Error: BAD TARGE input. The compartment specified by TARGET does not exist ',i0)
5051 format ('***Error: The key word ',a5,' is not recognized')
5062 format ('***Error: Bad COMPA input. Compartment number outside of allowable range ',i0)
5070 format ('***Error: Bad VENT input. Parameter(s) outside of allowable range',2I4)
5080 format ('***Error: Bad HVENT input. Too many pairwise horizontal connections',3I5)
5081 format ('***Error: Too many horizontal connections ',3i5)
5191 format ('***Error: Bad MVENT input. Compartments specified in MVENT have not been defined ',2i3)
5192 format ('***Error: Bad MVENT input. Exceeded maximum number of nodes/openings in MVENT ',2i3)
5193 format ('***Error: Bad MVENT input. MVENT(MID) is not consistent and should be a fan ',2i3)
5194 format ('***Error: Bad MVENT input. Pressure for zero flow must exceed the lower limit',f10.2)
5195 format ('***Error: Bad MVENT input. Too many fan systems ',i0)
5196 format ('***Error: Bad EVENT input. Fan has not been defined for this filter ',i0)
5300 format ('***Error: Bad FIRE input. Too many objects defined in datafile')
5310 format ('***Error: Bad FIRE input. Incorrect number of parameters for OBJECT')
5320 format ('***Error: Bad FIRE input. Fire specification error, room ',i0,' out of range')
5321 format ('***Error: Bad FIRE input. Fire specification error, not an allowed fire type',i0)
5322 format ('***Error: Bad FIRE input. Fire specification is outdated and must include target for ignition')
5323 format ('***Error: Bad FIRE input. Fire location ',i0,' is outside its compartment')
5324 format ('***Error: Bad FIRE input. Target specified for fire ',i0, ' does not exist')
5338 format ('***Error: Bad DETEC input. Exceed allowed number of detectors')
5339 format ('***Error: Bad DETEC input. Detector ',i0,' is outside of compartment ',a)
5342 format ('***Error: Bad DETEC input. Invalid DETECTOR specification - room ',i0)
5344 format ('***Error: Bad DETEC input. A referenced compartment is not yet defined ',i0)
5345 format ('***Error: Bad VHEAT input. A referenced compartment does not exist')
5346 format ('***Error: Bad HALL input. A referenced compartment does not exist ',i0)
5347 format ('***Error: Bad ROOMA input. Compartment specified by ROOMA does not exist ',i0)
5348 format ('***Error: Bad ROOMA or ROOMH input. Data on the ROOMA (or H) line must be positive ',1pg12.3)
5349 format ('***Error: Bad ROOMH input. Compartment specified by ROOMH is not defined ',i0)
5350 format ('***Error: Bad ROOMH input. ROOMH error on data line ',i0)
5354 format ('***Error: Bad HHEAT input. HHEAT to compartment out of bounds or not defined - ',i0)
5355 format ('***Error: Bad HHEAT input. HHEAT fraction pairs are not consistent ',2i3)
5356 format ('***Error: Bad HHEAT input. HHEAT specification error in compartment pairs: ',2i3)
5357 format ('***Error: Bad HHEAT input. Error in fraction for HHEAT:',2i3,f6.3)
5358 format ('***Error: Bad FIRE input. Not a valid ignition criterion ',i0)
5403 format ('***Error: Bad SLCF input. Invalid SLCF specification in visualization input ',i0)
5404 format ('***Error: Bad ISOF input. Invalid ISOF specification in visualization input ',i0)
5405 format ('***Error: Invalid or outdated keyword in CFAST input file ',a)
5406 format ('***Error: Bad HALL input. Outdated HALL command for compartment ',i0,' Flow inputs are no longer used')
5407 format ('***Warning: Outdated keyword in CFAST input file ignored ',a)

    end subroutine keywordcases

    ! --------------------------- inputembeddedfire -------------------------------------------

    subroutine inputembeddedfire(fireptr, lrowcount, inumc)

    !     routine: inputembeddedfire
    !     purpose: This routine reads a new format fire definition that begins with a FIRE keyword (already read in keywordcases)
    !              followed by CHEMI, TIME, HRR, SOOT, CO, TRACE, AREA, and HEIGH keywords (read in here)
    !     Arguments: fireptr: pointer to data for this fire object
    !                lrowcount: current row in the input file.  We begin one row after this one
    !                inumc:   number of columns in the input file
    !                iobj:    pointer to the fire object that will contain all the data we read in here

    integer, intent(in) :: inumc, lrowcount
    type(fire_type), intent(inout), pointer :: fireptr

    character(128) :: lcarray(ncol)
    character(5) :: label
    integer :: ir, i, nret
    real(eb) :: lrarray(ncol), ohcomb, max_area, max_hrr, hrrpm3, f_height
    type(room_type), pointer :: roomptr

    ! there are eight required inputs for each fire
    lrarray = 0.0_eb
    lcarray = ' '
    do ir = 1, 8
        label = carray(lrowcount+ir,1)
        if (label==' ') cycle
        do i = 2, inumc
            lcarray(i-1) = carray(lrowcount+ir,i)
            lrarray(i-1) = rarray(lrowcount+ir,i)
        end do

        select case (label)

            ! The new CHEMIE line defines chemistry for the current fire object.  This includes chemical formula,
            !  radiative fraction, heat of combustion, and material
        case ('CHEMI')
            if (countargs(lcarray)>=7) then
                ! define chemical formula
                fireptr%n_C = lrarray(1)
                fireptr%n_H = lrarray(2)
                fireptr%n_O = lrarray(3)
                fireptr%n_N = lrarray(4)
                fireptr%n_Cl = lrarray(5)
                fireptr%molar_mass = (12.01*fireptr%n_C + 1.008*fireptr%n_H + 16.0*fireptr%n_O + &
                    14.01*fireptr%n_N + 35.45*fireptr%n_Cl)/1000.0
                fireptr%chirad = lrarray(6)
                ohcomb = lrarray(7)
                if (ohcomb<=0.0_eb) then
                    write (*,5001) ohcomb
                    write (iofill,5001) ohcomb
                    stop
                end if
            else
                write (*,*) '***Error: At least 7 arguments required on CHEMI input'
                write (iofill,*) '***Error: At least 7 arguments required on CHEMI input'
                stop
            end if
        case ('TIME')
            nret = countargs(lcarray)
            fireptr%n_qdot = nret
            fireptr%t_qdot(1:nret) = lrarray(1:nret)
        case ('HRR')
            fireptr%qdot(1:nret) = lrarray(1:nret)
            fireptr%mdot(1:nret) = fireptr%qdot(1:nret)/ohcomb
            fireptr%t_mdot = fireptr%t_qdot
            fireptr%n_mdot = nret
            max_hrr = 0.0_eb
            do i = 1, nret
                max_hrr = max(max_hrr, fireptr%qdot(i))
            end do
        case ('SOOT')
                fireptr%y_soot(1:nret) = lrarray(1:nret)
                fireptr%t_soot = fireptr%t_qdot
                fireptr%n_soot = nret
        case ('CO')
                fireptr%y_co(1:nret) = lrarray(1:nret)
                fireptr%t_co = fireptr%t_qdot
                fireptr%n_co = nret
        case ('TRACE')
            ! Note that CT, TUHC and TS are carried in the mprodr array - all other species have their own array
                fireptr%y_trace(1:nret) = lrarray(1:nret)
                fireptr%t_trace = fireptr%t_qdot
                fireptr%n_trace = nret
        case ('AREA')
            max_area = 0.0_eb
            do i = 1, nret
                ! The minimum area is to stop dassl from a floating point underflow when it tries to extrapolate back to the
                ! ignition point. It only occurs for objects which are on the floor and ignite after t=0. The assumed minimum fire
                ! diameter of 0.2 m below is the minimum valid fire diameter for Heskestad's plume correlation
                ! (from SFPE Handbook chapter)
                if (lrarray(i)==0.0_eb) then
                    write (*,5002)
                    write (iofill,5002)
                    stop
                end if
                fireptr%area(i) = max(lrarray(i),pio4*0.2_eb**2)
                max_area = max(max_area,fireptr%area(i))
            end do
            fireptr%t_area = fireptr%t_qdot
                fireptr%n_area = nret

            ! calculate a characteristic length of an object (we assume the diameter).
            ! This is used for point source radiation fire to target calculation as a minimum effective
            ! distance between the fire and the target which only impact very small fire to target distances
            fireptr%characteristic_length = sqrt(max_area/pio4)
        case ('HEIGH')
                fireptr%height(1:nret) = lrarray(1:nret)
                fireptr%t_height = fireptr%t_qdot
                fireptr%n_height = nret
            case default
            write (*, 5000) label
            write (iofill, 5000) label
            stop
        end select

    end do

    ! set the heat of combustion - this is a problem if the qdot is zero and the mdot is zero as well
    call set_heat_of_combustion (fireptr%n_qdot, fireptr%mdot, fireptr%qdot, fireptr%hoc, ohcomb)
    fireptr%t_hoc = fireptr%t_qdot
    fireptr%n_hoc = fireptr%n_qdot

    ! Position the object
    roomptr => roominfo(fireptr%room)
    !call position_object (fireptr%x_position,roomptr%cwidth,midpoint,mx_hsep)
    !call position_object (fireptr%y_position,roomptr%cdepth,midpoint,mx_hsep)
    !call position_object (fireptr%z_position,roomptr%cheight,base,mx_hsep)

    ! diagnostic - check for the maximum heat release per unit volume.
    ! first, estimate the flame length - we want to get an idea of the size of the volume over which the energy will be released
    f_height = flame_height(max_hrr, max_area)
    f_height = max (0.0_eb, f_height)
    ! now the heat realease per cubic meter of the flame - we know that the size is larger than 1.0d-6 m^3 - enforced above
    hrrpm3 = max_hrr/(pio4*fireptr%characteristic_length**2*(fireptr%characteristic_length+f_height))
    if (hrrpm3>4.0e6_eb) then
        write (*,5106) trim(fireptr%name),fireptr%x_position,fireptr%y_position,fireptr%z_position,hrrpm3
        write (*, 5108)
        write (iofill,5106) trim(fireptr%name),fireptr%x_position,fireptr%y_position,fireptr%z_position,hrrpm3
        write (iofill, 5108)
        stop
    else if (hrrpm3>2.0e6_eb) then
        write (*,5107) trim(fireptr%name),fireptr%x_position,fireptr%y_position,fireptr%z_position,hrrpm3
        write (*, 5108)
        write (iofill,5107) trim(fireptr%name),fireptr%x_position,fireptr%y_position,fireptr%z_position,hrrpm3
        write (iofill, 5108)
    end if

    return
5001 format ('***Error: Invalid heat of combustion, must be greater than zero, ',1pg12.3)
5002 format ('***Error: Invalid fire area. All input values must be greater than zero')
5106 format ('***Error: Object ',a,' position set to ',3F7.3,'; Maximum HRR per m^3 = ',1pg10.3,' exceeds physical limits')
5107 format ('Object ',a,' position set to ',3F7.3,'; Maximum HRR per m^3 = ',1pg10.3,' exceeds nominal limits')
5108 format ('Typically, this is caused by too small fire area inputs. Check HRR and fire area inputs')
5000 format ('***Error: The key word ',a5,' is not part of a fire definition. Fire keyword are likely out of order')

    end subroutine inputembeddedfire

    ! --------------------------- readcsvformat -------------------------------------------

    subroutine readcsvformat (iunit, x, c, numr, numc, nstart, maxrow, maxcol, iofill)

    !     routine: readcsvformat
    !     purpose: reads a comma-delimited file as generated by Micorsoft Excel, assuming that all
    !              the data is in the form of real numbers
    !     arguments: iunit  = logical unit, already open to .csv file
    !                x      = array of dimension (numr,numc) for values in spreadsheet
    !                c      = character array of same dimenaion as x for character values in spreadsheet
    !                numr   = # of rows of array x
    !                numc   = # of columns of array x
    !                nstart = starting row of spreadsheet to read
    !                maxrow   = actual number of rows read
    !                maxcol   = actual number of columns read
    !                iofill   = logical unit number for writing error messages (if any)

    integer, intent(in) :: iunit, numr, numc, nstart, iofill

    integer, intent(out) :: maxrow, maxcol
    real(eb), intent(out) :: x(numr,numc)
    character, intent(out) :: c(numr,numc)*(*)

    character :: in*10000, token*128
    integer :: i, j, nrcurrent, ic, icomma, ios, nc

    maxrow = 0
    maxcol = 0
    do i=1,numr
        do j=1,numc
            x(i,j) = 0.0_eb
            c(i,j) = ' '
        end do
    end do

    ! if we have header rows, then skip them
    if (nstart>1) then
        do  i=1,nstart-1
            read (iunit,'(A)') in
        end do
    end if

    ! read the data
    nrcurrent = 0
20  read (iunit,'(A)',end=100) in

    ! Skip comments and blank lines
    if (in(1:1)=='!'.or.in(1:1)=='#'.or.in==' ') then
        go to 20
    end if

    nrcurrent = nrcurrent+1
    maxrow = max(maxrow,nrcurrent)

    ! Cannot exceed work array
    if (maxrow>numr) then
        write (*,'(a,i0,1x,i0)') '***Error: Too many rows or columns in input file, r,c = ', maxrow, maxcol
        write (iofill,'(a,i0,1x,i0)') '***Error: Too many rows or columns in input file, r,c = ', maxrow, maxcol
        stop
    end if

    nc=0
    ic=1
30  icomma=index(in,',')
    if (icomma/=0) then
        if (icomma==ic) then
            token=' '
        else
            token=in(ic:icomma-1)
        end if
        ic = icomma+1
        nc = nc + 1
        in(1:ic-1)=' '
        if (nrcurrent<=numr.and.nc<=numc) then
            c(nrcurrent,nc) = token
            read (token,'(f128.0)',iostat=ios) x(nrcurrent,nc)
            if (ios/=0) x(nrcurrent,nc) = 0
        else
            write (*,'(a,i0,a,i0)') 'Too many rows or columns in input file, r,c=', nrcurrent, ' ', nc
            write (iofill,'(a,i0,a,i0)') 'Too many rows or columns in input file, r,c=', nrcurrent, ' ', nc
            stop
        end if
        go to 30
    end if
    nc = nc + 1
    maxcol=max(maxcol,nc)
    token = in(ic:ic+100)
    c(nrcurrent,nc) = token
    read (token,'(f128.0)',iostat=ios) x(nrcurrent,nc)
    if (ios/=0) x(nrcurrent,nc) = 0
    go to 20

100 continue

    return
    end subroutine readcsvformat


    end module spreadsheet_input_routines