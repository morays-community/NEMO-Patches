MODULE infmod
   !!======================================================================
   !!                       ***  MODULE  infmod  ***
   !! Machine Learning Inferences : manage connexion with external ML codes 
   !!======================================================================
   !! History :  4.2.1  ! 2023-09  (A. Barge)  Original code
   !!----------------------------------------------------------------------

   !!----------------------------------------------------------------------
   !!   naminf          : machine learning models formulation namelist
   !!   inferences_init : initialization of Machine Learning based models
   !!   inferences      : ML based models
   !!   inf_snd         : send data to external trained model
   !!   inf_rcv         : receive inferences from external trained model
   !!----------------------------------------------------------------------
   USE oce             ! ocean fields
   USE dom_oce         ! ocean domain fields
   USE inffld          ! working fields for inferences models
   USE cpl_oasis3      ! OASIS3 coupling
   USE timing
   USE iom
   USE in_out_manager
   USE lib_mpp

   IMPLICIT NONE
   PRIVATE

   PUBLIC inf_alloc          ! function called in inferences_init 
   PUBLIC inf_dealloc        ! function called in inferences_final
   PUBLIC inferences_init    ! routine called in nemogcm.F90
   PUBLIC inferences         ! routine called in stpmlf.F90
   PUBLIC inferences_final   ! routine called in nemogcm.F90

   INTEGER, PARAMETER ::   jps_sst = 1    ! sea temperature
   INTEGER, PARAMETER ::   jps_uu = 2    ! sea salinity
   INTEGER, PARAMETER ::   jps_inf = 2   ! total number of sendings for inferences

   INTEGER, PARAMETER ::   jpr_sst = 1   ! density inferences-computed
   INTEGER, PARAMETER ::   jpr_uu = 2   ! density inferences-computed
   INTEGER, PARAMETER ::   jpr_inf = 2   ! total number of inference receptions

   INTEGER, PARAMETER ::   jpinf = MAX(jps_inf,jpr_inf) ! Maximum number of exchanges

   TYPE( DYNARR ), SAVE, DIMENSION(jpinf) ::  infsnd, infrcv  ! sent/received inferences

   !
   !!-------------------------------------------------------------------------
   !!                    Namelist for the Inference Models
   !!-------------------------------------------------------------------------
   !                           !!** naminf namelist **
   !TYPE ::   FLD_INF              !: Field informations ...  
   !   CHARACTER(len = 32) ::         ! 
   !END TYPE FLD_INF
   !
   LOGICAL , PUBLIC ::   ln_inf    !: activate module for inference models
   
   !!-------------------------------------------------------------------------

CONTAINS

   INTEGER FUNCTION inf_alloc()
      !!----------------------------------------------------------------------
      !!             ***  FUNCTION inf_alloc  ***
      !!----------------------------------------------------------------------
      INTEGER :: ierr
      INTEGER :: jn
      !!----------------------------------------------------------------------
      ierr = 0
      !
      DO jn = 1, jpinf
         IF( srcv(ntypinf,jn)%laction ) ALLOCATE( infrcv(jn)%z3(jpi,jpj,srcv(ntypinf,jn)%nlvl), STAT=ierr )
         IF( ssnd(ntypinf,jn)%laction ) ALLOCATE( infsnd(jn)%z3(jpi,jpj,ssnd(ntypinf,jn)%nlvl), STAT=ierr )
         inf_alloc = MAX(ierr,0)
      END DO
      !
   END FUNCTION inf_alloc

   
   INTEGER FUNCTION inf_dealloc()
      !!----------------------------------------------------------------------
      !!             ***  FUNCTION inf_dealloc  ***
      !!----------------------------------------------------------------------
      INTEGER :: ierr
      INTEGER :: jn
      !!----------------------------------------------------------------------
      ierr = 0
      !
      DO jn = 1, jpinf
         IF( srcv(ntypinf,jn)%laction ) DEALLOCATE( infrcv(jn)%z3, STAT=ierr )
         IF( ssnd(ntypinf,jn)%laction ) DEALLOCATE( infsnd(jn)%z3, STAT=ierr )
         inf_dealloc = MAX(ierr,0)
      END DO
      !
   END FUNCTION inf_dealloc


   SUBROUTINE inferences_init 
      !!----------------------------------------------------------------------
      !!             ***  ROUTINE inferences_init  ***
      !!
      !! ** Purpose :   Initialisation of the models that rely on external inferences
      !!
      !! ** Method  :   * Read naminf namelist
      !!                * create data for models
      !!----------------------------------------------------------------------
      !
      INTEGER ::   ios   ! Local Integer
      !!
      NAMELIST/naminf/  ln_inf
      !!----------------------------------------------------------------------
      !
      ! ================================ !
      !      Namelist informations       !
      ! ================================ !
      !
      REWIND( numnam_ref )
      READ  ( numnam_ref, naminf, IOSTAT = ios, ERR = 901)
901   IF( ios /= 0 )   CALL ctl_nam ( ios , 'naminf in reference namelist' )
      !
      REWIND( numnam_cfg )
      READ  ( numnam_cfg, naminf, IOSTAT = ios, ERR = 902 )
902   IF( ios >  0 )   CALL ctl_nam ( ios , 'naminf in configuration namelist' )
      IF( lwm ) WRITE ( numond, naminf )
      !
      IF( lwp ) THEN                        ! control print
         WRITE(numout,*)
         WRITE(numout,*)'inferences_init : Setting inferences models'
         WRITE(numout,*)'~~~~~~~~~~~~~~~'
      END IF
      IF ( lwp .AND. ln_inf ) THEN
         WRITE(numout,*)'   Namelist naminf'
         WRITE(numout,*)'      Module used       ln_inf        = ', ln_inf
         WRITE(numout,*)'      Models available:'
         WRITE(numout,*)'         Stanley et al. (2020)        = ', 'T by default for now'
      ENDIF
      !
      IF( ln_inf .AND. .NOT. lk_oasis )   CALL ctl_stop( 'inferences_init : External inferences coupled via OASIS, but key_oasis3 disabled' )
      !
      !
      ! ======================================== !
      !     Define exchange needs for Models     !
      ! ======================================== !
      !
      ! default definitions of ssnd snd srcv
      srcv(ntypinf,:)%laction = .FALSE.  ;  srcv(ntypinf,:)%clgrid = 'T'  ;  srcv(ntypinf,:)%nsgn = 1.
      srcv(ntypinf,:)%nct = 1  ;  srcv(ntypinf,:)%nlvl = 1
      !
      ssnd(ntypinf,:)%laction = .FALSE.  ;  ssnd(ntypinf,:)%clgrid = 'T'  ;  ssnd(ntypinf,:)%nsgn = 1.
      ssnd(ntypinf,:)%nct = 1  ;  ssnd(ntypinf,:)%nlvl = 1
      
      IF( ln_inf ) THEN
      
         ! -------------------------------- !
         !      Kenigson et al. (2022)      !
         ! -------------------------------- !

         ! sending of sea surface temparature
         ssnd(ntypinf,jps_sst)%clname = 'E_OUT_0'
         ssnd(ntypinf,jps_sst)%laction = .TRUE.

         ! sending of sea surface salinity
         ssnd(ntypinf,jps_uu)%clname = 'E_OUT_1'
         ssnd(ntypinf,jps_uu)%laction = .TRUE.
         ssnd(ntypinf,jps_uu)%clgrid = 'U'
         ssnd(ntypinf,jps_uu)%nlvl = 3

         ! reception of modified sea surface temperature
         srcv(ntypinf,jpr_sst)%clname = 'E_IN_0'
         srcv(ntypinf,jpr_sst)%laction = .TRUE.

         ! reception of 3 first levels of modified velocity         
         srcv(ntypinf,jpr_uu)%clname = 'E_IN_1'
         srcv(ntypinf,jpr_uu)%laction = .TRUE.
         srcv(ntypinf,jpr_uu)%clgrid = 'U'
         srcv(ntypinf,jpr_uu)%nlvl = 3

         ! ------------------------------ !
         ! ------------------------------ !

      END IF
      ! 
      ! ================================= !
      !   Define variables for coupling
      ! ================================= !
      CALL cpl_var(jpinf, jpinf, 1, ntypinf)
      !
      IF( inf_alloc() /= 0 )     CALL ctl_stop( 'STOP', 'inf_alloc : unable to allocate arrays' )
      IF( inffld_alloc() /= 0 )  CALL ctl_stop( 'STOP', 'inffld_alloc : unable to allocate arrays' ) 
      !
   END SUBROUTINE inferences_init


   SUBROUTINE inferences( kt, Kbb, Kmm, Kaa )
      !!----------------------------------------------------------------------
      !!             ***  ROUTINE inferences  ***
      !!
      !! ** Purpose :   update the ocean data with the ML based models
      !!
      !! ** Method  :   *  
      !!                * 
      !!----------------------------------------------------------------------
      INTEGER, INTENT(in) ::   kt            ! ocean time step
      INTEGER, INTENT(in) ::   Kbb, Kmm, Kaa ! ocean time level indices
      !
      INTEGER :: isec, info, jn                       ! local integer
      REAL(wp), DIMENSION(jpi,jpj,jpk)   ::  zdata    ! sending buffer
      !!----------------------------------------------------------------------
      !
      IF( ln_timing )   CALL timing_start('inferences')
      !
      isec = ( kt - nit000 ) * NINT( rdt )       ! Date of exchange 
      info = OASIS_idle
      !
      ! ------  Prepare data to send ------
      !
      ! Sea Surface Temperature
      IF( ssnd(ntypinf,jps_sst)%laction ) THEN
         infsnd(jps_sst)%z3(:,:,1:ssnd(ntypinf,jps_sst)%nlvl) = tsn(:,:,1:ssnd(ntypinf,jps_sst)%nlvl,jp_tem)
      ENDIF  
      !
      ! 3 first levels of sea velocity
      IF( ssnd(ntypinf,jps_uu)%laction ) THEN
         infsnd(jps_uu)%z3(:,:,1:ssnd(ntypinf,jps_uu)%nlvl) = ub(:,:,1:ssnd(ntypinf,jps_uu)%nlvl)
      ENDIF
      !
      ! ========================
      !   Proceed all sendings
      ! ========================
      !
      DO jn = 1, jpinf
         IF ( ssnd(ntypinf,jn)%laction ) THEN
            CALL cpl_snd( jn, isec, ntypinf, infsnd(jn)%z3, info)
         ENDIF
      END DO
      !
      ! .... some external operations ....
      !
      ! ==========================
      !   Proceed all receptions
      ! ==========================
      !
      DO jn = 1, jpinf
         IF( srcv(ntypinf,jn)%laction ) THEN
            CALL cpl_rcv( jn, isec, ntypinf, infrcv(jn)%z3, info)
         ENDIF
      END DO
      !
      ! ------ Distribute receptions  ------
      !
      ! Sea Surface temperature
      IF( srcv(ntypinf,jpr_sst)%laction ) THEN
         ext_ts_2D(:,:) = infrcv(jpr_sst)%z3(:,:,1)
         CALL iom_put( 'Ext_SST', ext_ts_2D(:,:) )
      ENDIF
      ! 3 first levels of velocity
      IF( srcv(ntypinf,jpr_uu)%laction ) THEN
         ext_u_3D(:,:,1:srcv(ntypinf,jpr_uu)%nlvl) = infrcv(jpr_sst)%z3(:,:,1:srcv(ntypinf,jpr_uu)%nlvl)
         CALL iom_put( 'Ext_uu', ext_u_3D(:,:,:) )
      ENDIF
      !
      IF( ln_timing )   CALL timing_stop('inferences')
      !
   END SUBROUTINE inferences


   SUBROUTINE inferences_final
      !!----------------------------------------------------------------------
      !!             ***  ROUTINE inferences_final  ***
      !!
      !! ** Purpose :   Free memory used for inferences modules
      !!
      !! ** Method  :   * Deallocate arrays
      !!----------------------------------------------------------------------
      !
      IF( inf_dealloc() /= 0 )     CALL ctl_stop( 'STOP', 'inf_dealloc : unable to free memory' )
      IF( inffld_dealloc() /= 0 )  CALL ctl_stop( 'STOP', 'inffld_dealloc : unable to free memory' )      
      !
   END SUBROUTINE inferences_final 
   !!=======================================================================
END MODULE infmod
