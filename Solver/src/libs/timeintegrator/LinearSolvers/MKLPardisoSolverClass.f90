!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
!      MKLPardisoSolverClass.f90
!      Created: 2017-04-10 10:006:00 +0100 
!      By: Andrés Rueda
!
!      Class for solving linear systems using MKL version of Pardiso
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#ifdef HAS_PETSC
#include "petsc/finclude/petsc.h"
#endif
MODULE MKLPardisoSolverClass
   USE GenericLinSolverClass
   USE CSRMatrixClass
   use PETScMatrixClass
   USE SMConstants
   use DGSEMClass
   use TimeIntegratorDefinitions
   use NumericalJacobian
#ifdef HAS_PETSC
   use petsc
#endif
   IMPLICIT NONE
   
   TYPE, EXTENDS(GenericLinSolver_t) :: MKLPardisoSolver_t
      TYPE(csrMat_t)                             :: A                                  ! Jacobian matrix
      type(PETSCMatrix_t)                        :: PETScA
      REAL(KIND=RP), DIMENSION(:), ALLOCATABLE   :: x                                  ! Solution vector
      REAL(KIND=RP), DIMENSION(:), ALLOCATABLE   :: b                                  ! Right hand side
      REAL(KIND=RP)                              :: Ashift
      LOGICAL                                    :: AIsPrealloc   
      TYPE(DGSem), POINTER                       :: p_sem
      
      !Variables for creating Jacobian in PETSc context:
      LOGICAL                                    :: AIsPetsc = .TRUE.
      
      !Variables directly related with mkl pardiso solver
      INTEGER                                    :: mtype                              ! Matrix type. See construct
      INTEGER, ALLOCATABLE                       :: perm(:)
      INTEGER, POINTER                           :: Pardiso_iparm(:) => NULL()         ! Parameters for mkl version of pardiso
      INTEGER(KIND=AddrInt), POINTER             :: Pardiso_pt(:)    => NULL()  
   CONTAINS
      !Subroutines:
      PROCEDURE :: construct => ConstructMKLContext
      procedure :: ComputeAndFactorizeJacobian => MKL_ComputeAndFactorizeJacobian
      PROCEDURE :: SetBValue
      PROCEDURE :: solve
      procedure :: SolveLUDirect => MKL_SolveLUDirect
      PROCEDURE :: GetXValue
      PROCEDURE :: destroy
      PROCEDURE :: SetOperatorDt
      PROCEDURE :: ReSetOperatorDt
      !Functions:
      PROCEDURE :: Getxnorm    !Get solution norm
      PROCEDURE :: Getrnorm    !Get residual norm
   END TYPE MKLPardisoSolver_t
   
   PRIVATE
   PUBLIC MKLPardisoSolver_t, GenericLinSolver_t
   
   
!========
 CONTAINS
!========
   
   SUBROUTINE ConstructMKLContext(this,DimPrb,controlVariables,sem)
      IMPLICIT NONE
      !-----------------------------------------------------------
      CLASS(MKLPardisoSolver_t), INTENT(INOUT), TARGET :: this
      INTEGER                  , INTENT(IN)            :: DimPrb
      TYPE(FTValueDictionary)  , INTENT(IN), OPTIONAL  :: controlVariables
      TYPE(DGSem), TARGET                  , OPTIONAL  :: sem
      !-----------------------------------------------------------
      INTERFACE
         SUBROUTINE pardisoinit(pt, mtype, iparm)
            USE SMConstants
            IMPLICIT NONE
            INTEGER(KIND=AddrInt) :: pt(*)
            INTEGER :: mtype
            INTEGER :: iparm(*)
         END SUBROUTINE pardisoinit
      END INTERFACE
      !-----------------------------------------------------------
!
!     PETSc requires initialization
!     -----------------------------
#ifdef HAS_PETSC
      PetscErrorCode :: ierr
      CALL PetscInitialize(PETSC_NULL_CHARACTER,ierr)
#endif

      this % p_sem => sem
      
      this % DimPrb = DimPrb
      
      ALLOCATE(this % x(DimPrb))
      ALLOCATE(this % b(DimPrb))
      
      this % mtype = 11 !Set matrix type to real unsymmetric (change?)
    
      ALLOCATE(this % Pardiso_pt(64))
      ALLOCATE(this % Pardiso_iparm(64))
      
      ALLOCATE(this % perm(DimPrb))
      this % perm = 0
      
      IF(this % AIsPetsc) then
         CALL this % PETScA % construct (DimPrb,.FALSE.)
      end if

#ifdef HAS_MKL
      CALL pardisoinit(this % Pardiso_pt, this % mtype, this % Pardiso_iparm)
#else
      STOP 'MKL not linked correctly'
#endif
   END SUBROUTINE ConstructMKLContext
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   SUBROUTINE SetBValue(this, irow, value)
      IMPLICIT NONE
      !-----------------------------------------------------------
      CLASS(MKLPardisoSolver_t), INTENT(INOUT) :: this
      INTEGER                  , INTENT(IN)    :: irow
      REAL(KIND=RP)            , INTENT(IN)    :: value
      !-----------------------------------------------------------
      
      this % b (irow+1) = value
      
   END SUBROUTINE SetBValue
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
   SUBROUTINE SetBValues(this, nvalues, irow, values)
      CLASS(MKLPardisoSolver_t)   , INTENT(INOUT)     :: this
      INTEGER                     , INTENT(IN)        :: nvalues
      INTEGER      , DIMENSION(1:), INTENT(IN)        :: irow
      REAL(KIND=RP), DIMENSION(1:), INTENT(IN)        :: values
      !------------------------------------------------------
      INTEGER                                        :: i
      
      DO i=1, nvalues
         IF (irow(i)<0) CYCLE
         this % b(irow(i)+1) = values(i)
      END DO
      
   END SUBROUTINE SetBValues
   !~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   SUBROUTINE solve(this,tol,maxiter,time,dt, ComputeTimeDerivative,ComputeA) 
      IMPLICIT NONE
!
!     ----------------------------------------------------
!     Main subroutine for solving system using mkl pardiso
!     ----------------------------------------------------
!
      !-----------------------------------------------------------
      CLASS(MKLPardisoSolver_t), INTENT(INOUT) :: this
      REAL(KIND=RP), OPTIONAL                  :: tol
      INTEGER      , OPTIONAL                  :: maxiter
      REAL(KIND=RP), OPTIONAL                  :: time
      REAL(KIND=RP), OPTIONAL                  :: dt
      procedure(ComputeQDot_FCN)              :: ComputeTimeDerivative
      logical      , optional      , intent(inout) :: ComputeA
      !-----------------------------------------------------------
#ifdef HAS_MKL
      INTEGER                                  :: error
      !-----------------------------------------------------------
      INTERFACE
         SUBROUTINE pardiso(pt, maxfct, mnum, mtype, phase, n, &
                           values, rows, cols, perm, nrhs, iparm, msglvl, b, x, ierror)
            USE SMConstants
            IMPLICIT NONE
            REAL(KIND=RP) :: values(*), b(*), x(*)
            INTEGER(KIND=AddrInt) :: pt(*)
            INTEGER :: perm(*), nrhs, iparm(*), msglvl, ierror
            INTEGER :: maxfct, mnum, mtype, phase, n, rows(*), cols(*)
         END SUBROUTINE pardiso
      END INTERFACE
      !-----------------------------------------------------------
      
!
!     Compute Jacobian matrix if needed
!        (done in petsc format and then transformed to CSR since the CSR cannot be filled by the Jacobian calculators)
!     -----------------------------------------------------
      
      if ( present(ComputeA)) then
         if (ComputeA) then
            call NumericalJacobian_Compute(this % p_sem, time, this % PETScA, ComputeTimeDerivative, .TRUE. )
            call this % PETScA % shift(-1._RP/dt)
            call this % PETScA % GetCSRMatrix(this % A)
            this % AIsPetsc = .FALSE.
            ComputeA = .FALSE.
         end if
      else 
         call NumericalJacobian_Compute(this % p_sem, time, this % A, ComputeTimeDerivative, .TRUE. )
         call this % PETScA % shift(-1._RP/dt)
         call this % PETScA % GetCSRMatrix(this % A)
      end if
      
!~    	call mkl_set_num_threads( 4 )
      
      !-----------------------
      ! Solve the system using MKL - Pardiso!!
!~    phase = 33            ! Solve, iterative refinement
      CALL pardiso(  pt      = this % Pardiso_pt    ,     &
                     maxfct  = 1                    ,     &     ! Set up space for 1 matrix at most
                     mnum    = 1                    ,     &     ! Matrix to use in the solution phase (1st and only one)
                     mtype   = this % mtype         ,     &
                     phase   = 13                   ,     &     !  
                     n       = this % DimPrb        ,     &     ! Number of equations
                     values  = this % A % Values    ,     & 
                     rows    = this % A % Rows      ,     &
                     cols    = this % A % Cols      ,     &
                     perm    = this % perm          ,     &     ! ...
                     nrhs    = 1                    ,     &     ! Only one right hand side 
                     iparm   = this % Pardiso_iparm ,     &
                     msglvl  = 0                    ,     &     ! 1: verbose... Too much printing
                     b       = this % b             ,     &
                     x       = this % x             ,     &
                     ierror  = error              )
                
!~    msglvl    = 0 ! Do not write out any info
!~    nrhs      = 1 ! Use only one RHS

      IF (error .NE. 0) THEN
         WRITE(*,*) 'MKL Pardiso ERROR:', error
         STOP
      ELSE
         this % converged = .TRUE.
      END IF
    
#else
      STOP 'MKL is not linked properly'
#endif
      
   END SUBROUTINE solve
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   SUBROUTINE GetXValue(this,irow,x_i)       
      IMPLICIT NONE
      !-----------------------------------------------------------
      CLASS(MKLPardisoSolver_t), INTENT(INOUT) :: this
      INTEGER                  , INTENT(IN)    :: irow
      REAL(KIND=RP)            , INTENT(OUT)   :: x_i
      !-----------------------------------------------------------
      
      x_i = this % x(irow+1)
      
   END SUBROUTINE GetXValue
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   SUBROUTINE destroy(this)       
      IMPLICIT NONE
      !-----------------------------------------------------------
      CLASS(MKLPardisoSolver_t), INTENT(INOUT) :: this
      !-----------------------------------------------------------
      
      CALL this % A % destruct
      
      DEALLOCATE(this % b)
      DEALLOCATE(this % x)
      DEALLOCATE(this % Pardiso_pt)
      DEALLOCATE(this % Pardiso_iparm)
      DEALLOCATE(this % perm)
      
      CALL this % PETScA % destruct
      this % AIsPetsc    = .TRUE.
      this % AIsPrealloc = .FALSE.
      
    END SUBROUTINE destroy
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   SUBROUTINE SetOperatorDt(this,dt)       
      IMPLICIT NONE
      !-----------------------------------------------------------
      CLASS(MKLPardisoSolver_t), INTENT(INOUT) :: this
      REAL(KIND=RP)            , INTENT(IN)    :: dt
      !-----------------------------------------------------------
      
      this % Ashift = -1._RP/dt
      IF (this % AIsPetsc) THEN
         CALL this % PETScA % shift(this % Ashift)
      ELSE
         CALL this % A % Shift(this % Ashift)
      END IF
      
    END SUBROUTINE SetOperatorDt
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   SUBROUTINE ReSetOperatorDt(this,dt)       
      IMPLICIT NONE
      !-----------------------------------------------------------
      CLASS(MKLPardisoSolver_t), INTENT(INOUT) :: this
      REAL(KIND=RP)            , INTENT(IN)    :: dt
      !-----------------------------------------------------------
      REAL(KIND=RP)                            :: shift
      !-----------------------------------------------------------
      
      shift = -1._RP/dt
      IF (this % AIsPetsc) THEN
         CALL this % PETScA % shift(shift)
      ELSE
         CALL this % A % Shift(-this % Ashift)
         CALL this % A % Shift(shift)
      END IF
      this % Ashift = shift
      
    END SUBROUTINE ReSetOperatorDt
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   FUNCTION Getxnorm(this,TypeOfNorm) RESULT(xnorm)
      IMPLICIT NONE
      !-----------------------------------------------------------
      CLASS(MKLPardisoSolver_t), INTENT(INOUT) :: this
      CHARACTER(len=*)                         :: TypeOfNorm
      REAL(KIND=RP)                            :: xnorm
      !-----------------------------------------------------------
      
      SELECT CASE (TypeOfNorm)
         CASE ('infinity')
            xnorm = MAXVAL(ABS(this % x))
         CASE ('l2')
            xnorm = NORM2(this % x)
         CASE DEFAULT
            STOP 'MKLPardisoSolverClass ERROR: Norm not implemented yet'
      END SELECT
   END FUNCTION Getxnorm
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
   FUNCTION Getrnorm(this) RESULT(rnorm)
      IMPLICIT NONE
!
!     ----------------------------------------
!     Currently implemented with infinity norm
!     ----------------------------------------
!
      !-----------------------------------------------------------
      CLASS(MKLPardisoSolver_t), INTENT(INOUT) :: this
      REAL(KIND=RP)                            :: rnorm
      !-----------------------------------------------------------
      REAL(KIND=RP)                            :: residual(this % DimPrb)
      !-----------------------------------------------------------
      
      residual = this % b - CSR_MatVecMul(this % A, this % x)
      rnorm = MAXVAL(ABS(residual))
      
      
      !rnorm = NORM2(this % x)
      
   END FUNCTION Getrnorm
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!

   subroutine MKL_ComputeAndFactorizeJacobian(self, F_J, dt, eps)
!
!     *************************************************************************************
!     This subroutine performs the following:
!           -> Construct the numerical Jacobian of the function F_J, with perturbation eps.
!           -> Shifts the Jacobian -dt * I.
!           -> Converts the Jacobian to CSR.
!           -> Factorizes the Jacobian (jobs 12 in Pardiso).
!
!     *************************************************************************************
!
      implicit none
      class(MKLPardisoSolver_t), intent(inout) :: self
      procedure(ComputeQDot_FCN)               :: F_J
      real(kind=RP), intent(in)                :: dt
      real(kind=RP), intent(in)                :: eps
!
!     ---------------
!     Local variables
!     ---------------
!
      integer     :: error
!
!     Compute numerical Jacobian in the PETSc matrix
!     ----------------------------------------------
      call NumericalJacobian_Compute(self % p_sem, 0.0_RP, self % PETScA, F_J, .true., eps)
!
!     Shift the Jacobian
!     ------------------
      call self % PETScA % shift(-1.0_RP/dt)
!
!     Transform the Jacobian to CSRMatrix
!     -----------------------------------
      call self % PETScA % GetCSRMatrix(self % A)
!
!     Correct the shifted Jacobian values
!     -----------------------------------
      self % A % values = -dt * self % A % values
!
!     Perform the factorization
!     -------------------------
#ifdef HAS_MKL
      call pardiso(self % Pardiso_pt, 1, 1, self % mtype, 12, self % A % NumRows, self % A % values, &
                   self % A % rows, self % A % cols, self % perm, 1, self % Pardiso_iparm, 0, &
                   self % b, self % x, error)
#else
      STOP 'MKL not linked correctly'
#endif

   end subroutine MKL_ComputeAndFactorizeJacobian

   subroutine MKL_SolveLUDirect(self)
      implicit none
      class(MKLPardisoSolver_t), intent(inout)  :: self
!
!     ---------------
!     Local variables
!     ---------------
!
      integer     :: error

#ifdef HAS_MKL
      call pardiso(self % Pardiso_pt, 1, 1, self % mtype, 33, self % A % NumRows, self % A % values, &
                   self % A % rows, self % A % cols, self % perm, 1, self % Pardiso_iparm, 0, &
                   self % b, self % x, error)
#else
      STOP 'MKL not linked correctly'
#endif
   end subroutine MKL_SolveLUDirect

END MODULE MKLPardisoSolverClass
