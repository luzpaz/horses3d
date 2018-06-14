!////////////////////////////////////////////////////////////////////////
!
!      LinkedListMatrixClass.f90
!      Created: 2018-02-19 17:07:00 +0100 
!      By: Andrés Rueda
!
!      Linked list matrix
!
!////////////////////////////////////////////////////////////////////////
module LinkedListMatrixClass
   use SMConstants
   use GenericMatrixClass
   use Jacobian, only: JACEPS
   implicit none
   
   private
   public LinkedListMatrix_t
   
   !-----------------
   ! Type for entries
   !-----------------
   type Entry_t
      real(kind=RP)  :: value
      integer        :: col
      class(Entry_t), pointer    :: next => NULL()
   end type Entry_t
   
   !--------------
   ! Type for rows
   !--------------
   type Row_t
      type(Entry_t), pointer :: head
      integer :: num_of_entries
   end type Row_t
   
   !------------------------------
   ! Main type: Linked list matrix
   !------------------------------
   type, extends(Matrix_t) :: LinkedListMatrix_t
      type(Row_t), allocatable :: rows(:)
      integer                  :: num_of_entries
      contains
      procedure :: construct
      procedure :: setEntry
      procedure :: destruct
      procedure :: PointToEntry
      procedure :: getCSRarrays
   end type LinkedListMatrix_t
   
contains
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
!  -------------------------------------
!  Constructor
!  -------------------------------------
   subroutine construct(this,dimPrb,withMPI)
      implicit none
      !-arguments-----------------------------------
      class(LinkedListMatrix_t)     :: this     !<> This matrix
      integer          , intent(in) :: dimPrb   !<  Number of blocks of the matrix!
      logical, optional, intent(in) :: WithMPI
      !-local-variables-----------------------------
      integer :: i
      !---------------------------------------------
      
      this % NumRows = dimPrb
      
      allocate ( this % rows(dimPrb) )
      do i=1, dimPrb
         this % rows(i) % num_of_entries = 0
      end do
      
   end subroutine construct
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
!  -------------------------------
!  Set entry of linked-list matrix
!  ------------------------------- 
   subroutine SetEntry(this, row, col, value )
      implicit none
      !-arguments-----------------------------------
      class(LinkedListMatrix_t), intent(inout) :: this
      integer        , intent(in)    :: row
      integer        , intent(in)    :: col
      real(kind=RP)  , intent(in)    :: value
      !-local-variables------------------------------
      type(Entry_t), pointer :: Entry
      !----------------------------------------------
      
      if (value < JACEPS) return
      
      Entry => this % PointToEntry(row,col)
      Entry % value = value
      
   end subroutine SetEntry
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
!  -------------------------------
!  Set entry of linked-list matrix
!  ------------------------------- 
   subroutine destruct(this)
      implicit none
      !-arguments-----------------------------------
      class(LinkedListMatrix_t), intent(inout) :: this
      !-local-variables------------------------------
      type(Entry_t), pointer :: Centry, next
      integer       :: i
      !----------------------------------------------
      
      do i=1, this % NumRows
         CEntry => this % rows(i) % head
         do while ( associated(CEntry) )
            next => CEntry % next
            deallocate(CEntry)
            Centry => next
         end do
      end do
      
      deallocate ( this % rows )
      
   end subroutine destruct
   
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
!  -----------------------------------------------------------
!  Function to point to a specific entry of the matrix. If the
!  entry has not been created, then it creates it 
!  -----------------------------------------------------------
   function PointToEntry(Matrix,i,j ) result(Entry)
      implicit none
      !-arguments------------------------------------------------------
      class(LinkedListMatrix_t), intent(inout) :: Matrix
      integer                 , intent(in)     :: i,j
      type(Entry_t)           , pointer        :: Entry
      !-local-variables------------------------------------------------
      type(Entry_t), pointer :: CEntry, Prev
      !----------------------------------------------------------------
     
      CEntry => Matrix % rows(i) % head

      nullify(Prev)
      
      do while( associated(CEntry) )
         if ( CEntry % col >= j ) exit
         Prev   => CEntry
         CEntry => CEntry % next
      end do

      if ( associated(CEntry) ) then
         if ( CEntry % col == j ) then
            Entry => CEntry
            return
         end if
      end if

      allocate( Entry )
      Entry % Value = 0._RP
      Entry % col = j
      Entry % next => CEntry
      
      if ( associated(Prev) ) then
         Prev % next => Entry
      else
         Matrix % rows(i) % head => Entry
      end if
      
      Matrix % rows(i) % num_of_entries = Matrix % rows(i) % num_of_entries + 1
      Matrix % num_of_entries = Matrix % num_of_entries + 1
      
   end function PointToEntry
!
!///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
!
!  ----------------------------------------
!  Convert linked list matrix to CSR matrix
!  ----------------------------------------
   subroutine getCSRarrays(this,Values,Cols,Rows)
      implicit none
      !-arguments------------------------------------------------------
      class(LinkedListMatrix_t), intent(inout)  :: this
      real(kind=RP), dimension(:), allocatable  :: Values
      integer      , dimension(:), allocatable  :: Cols, Rows
      !-local-variables------------------------------------------------
      integer :: i, j
      type(Entry_t), pointer :: CEntry
      !----------------------------------------------------------------
      
      allocate ( Rows(this % NumRows + 1) )
      allocate ( Cols(this % num_of_entries) )
      allocate ( Values(this % num_of_entries) )
      
!     Set first row
!     -------------
      
      Rows(1) = 1
      CEntry => this % rows(1) % head
      do j=0, this % rows(1) % num_of_entries - 1
         Values(Rows(i)+j) = CEntry % value
         Cols  (Rows(i)+j) = CEntry % col
         
         CEntry => CEntry % next
      end do
      
!     Set the rest
!     ------------
      
      do i=2, this % NumRows
         Rows(i) = Rows(i-1) + this % rows(i-1) % num_of_entries
         
         CEntry => this % rows(i) % head
         do j=0, this % rows(i) % num_of_entries - 1
            Values(Rows(i)+j) = CEntry % value
            Cols  (Rows(i)+j) = CEntry % col
            
            CEntry => CEntry % next
         end do
      end do
      
      Rows(this % NumRows + 1) = Rows(this % NumRows) + this % rows(this % NumRows) % num_of_entries
      
   end subroutine getCSRarrays
end module LinkedListMatrixClass
