;; Peer Review System Contract
;; Smart contract enabling blind peer reviews and reviewer incentives

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_REVIEW_NOT_FOUND (err u201))
(define-constant ERR_PAPER_NOT_FOUND (err u202))
(define-constant ERR_REVIEWER_NOT_FOUND (err u203))
(define-constant ERR_ALREADY_REVIEWED (err u204))
(define-constant ERR_INVALID_SCORE (err u205))
(define-constant ERR_REVIEW_CLOSED (err u206))
(define-constant ERR_INSUFFICIENT_REVIEWS (err u207))
(define-constant ERR_INVALID_INPUT (err u208))
(define-constant ERR_REVIEWER_EXISTS (err u209))

;; Review Status Constants
(define-constant STATUS_PENDING "pending")
(define-constant STATUS_IN_REVIEW "in-review")
(define-constant STATUS_REVIEWED "reviewed")
(define-constant STATUS_ACCEPTED "accepted")
(define-constant STATUS_REJECTED "rejected")

;; Scoring Constants
(define-constant MIN_SCORE u1)
(define-constant MAX_SCORE u10)
(define-constant REQUIRED_REVIEWS u3)
(define-constant REVIEWER_REWARD u100)
(define-constant QUALITY_THRESHOLD u70)

;; Data Variables
(define-data-var review-counter uint u0)
(define-data-var reviewer-counter uint u0)
(define-data-var total-reviews uint u0)

;; Data Maps
(define-map Reviews
  { review-id: uint }
  {
    paper-id: uint,
    reviewer: principal,
    score: uint,
    comments: (string-ascii 1000),
    recommendation: (string-ascii 20),
    timestamp: uint,
    quality-score: uint,
    is-anonymous: bool
  }
)

(define-map PaperReviews
  { paper-id: uint }
  {
    review-ids: (list 10 uint),
    status: (string-ascii 20),
    total-reviews: uint,
    average-score: uint,
    submission-timestamp: uint,
    deadline: uint
  }
)

(define-map Reviewers
  { reviewer: principal }
  {
    reputation-score: uint,
    total-reviews: uint,
    specializations: (list 5 (string-ascii 30)),
    is-active: bool,
    registration-timestamp: uint,
    total-earnings: uint
  }
)

(define-map ReviewerAssignments
  { paper-id: uint, reviewer: principal }
  {
    assigned-timestamp: uint,
    deadline: uint,
    is-completed: bool,
    review-id: (optional uint)
  }
)

(define-map ReviewQualities
  { review-id: uint }
  {
    helpfulness-score: uint,
    accuracy-score: uint,
    timeliness-score: uint,
    overall-quality: uint
  }
)

(define-map PaperReviewerPool
  { paper-id: uint }
  { assigned-reviewers: (list 10 principal) }
)

;; Private Functions
(define-private (increment-review-counter)
  (let ((current-count (var-get review-counter)))
    (var-set review-counter (+ current-count u1))
    (+ current-count u1)
  )
)

(define-private (increment-reviewer-counter)
  (let ((current-count (var-get reviewer-counter)))
    (var-set reviewer-counter (+ current-count u1))
    (+ current-count u1)
  )
)

(define-private (calculate-average-score (scores (list 10 uint)))
  (if (> (len scores) u0)
    (/ (fold + scores u0) (len scores))
    u0
  )
)

(define-private (is-reviewer-assigned (paper-id uint) (reviewer principal))
  (is-some (map-get? ReviewerAssignments { paper-id: paper-id, reviewer: reviewer }))
)

(define-private (has-reviewer-submitted (paper-id uint) (reviewer principal))
  (match (map-get? ReviewerAssignments { paper-id: paper-id, reviewer: reviewer })
    assignment (get is-completed assignment)
    false
  )
)

(define-private (update-reviewer-stats (reviewer principal) (quality-score uint))
  (let (
    (current-stats (unwrap! (map-get? Reviewers { reviewer: reviewer }) false))
    (new-total (+ (get total-reviews current-stats) u1))
    (current-rep (get reputation-score current-stats))
    (new-rep (/ (+ (* current-rep (get total-reviews current-stats)) quality-score) new-total))
  )
    (map-set Reviewers
      { reviewer: reviewer }
      (merge current-stats {
        reputation-score: new-rep,
        total-reviews: new-total,
        total-earnings: (+ (get total-earnings current-stats) REVIEWER_REWARD)
      })
    )
    true
  )
)

(define-private (calculate-review-quality (review-id uint) (helpfulness uint) (accuracy uint) (timeliness uint))
  (let (
    (overall (/ (+ helpfulness accuracy timeliness) u3))
  )
    (map-set ReviewQualities
      { review-id: review-id }
      {
        helpfulness-score: helpfulness,
        accuracy-score: accuracy,
        timeliness-score: timeliness,
        overall-quality: overall
      }
    )
    overall
  )
)

;; Public Functions
(define-public (register-reviewer
    (specializations (list 5 (string-ascii 30)))
  )
  (let (
    (reviewer tx-sender)
  )
    ;; Check if reviewer already exists
    (asserts! (is-none (map-get? Reviewers { reviewer: reviewer })) ERR_REVIEWER_EXISTS)
    
    ;; Register the reviewer
    (map-set Reviewers
      { reviewer: reviewer }
      {
        reputation-score: u50,
        total-reviews: u0,
        specializations: specializations,
        is-active: true,
        registration-timestamp: stacks-block-height,
        total-earnings: u0
      }
    )
    
    (increment-reviewer-counter)
    (ok true)
  )
)

(define-public (submit-for-review
    (paper-id uint)
    (review-deadline uint)
  )
  (let (
    (submission-time stacks-block-height)
    (deadline (+ submission-time review-deadline))
  )
    ;; Validate input
    (asserts! (> paper-id u0) ERR_INVALID_INPUT)
    (asserts! (> review-deadline u0) ERR_INVALID_INPUT)
    
    ;; Initialize paper review tracking
    (map-set PaperReviews
      { paper-id: paper-id }
      {
        review-ids: (list),
        status: STATUS_PENDING,
        total-reviews: u0,
        average-score: u0,
        submission-timestamp: submission-time,
        deadline: deadline
      }
    )
    
    (ok true)
  )
)

(define-public (assign-reviewer
    (paper-id uint)
    (reviewer principal)
    (assignment-deadline uint)
  )
  (let (
    (assignment-time stacks-block-height)
    (deadline (+ assignment-time assignment-deadline))
  )
    ;; Validate reviewer exists and is active
    (let (
      (reviewer-data (unwrap! (map-get? Reviewers { reviewer: reviewer }) ERR_REVIEWER_NOT_FOUND))
    )
      (asserts! (get is-active reviewer-data) ERR_REVIEWER_NOT_FOUND)
    )
    
    ;; Check if reviewer is not already assigned
    (asserts! (not (is-reviewer-assigned paper-id reviewer)) ERR_UNAUTHORIZED)
    
    ;; Assign reviewer
    (map-set ReviewerAssignments
      { paper-id: paper-id, reviewer: reviewer }
      {
        assigned-timestamp: assignment-time,
        deadline: deadline,
        is-completed: false,
        review-id: none
      }
    )
    
    ;; Update paper status
    (match (map-get? PaperReviews { paper-id: paper-id })
      paper-review
        (map-set PaperReviews
          { paper-id: paper-id }
          (merge paper-review { status: STATUS_IN_REVIEW })
        )
      false
    )
    
    ;; Add to reviewer pool
    (let (
      (current-pool (default-to (list) (get assigned-reviewers (map-get? PaperReviewerPool { paper-id: paper-id }))))
      (updated-pool (unwrap! (as-max-len? (append current-pool reviewer) u10) ERR_INVALID_INPUT))
    )
      (map-set PaperReviewerPool { paper-id: paper-id } { assigned-reviewers: updated-pool })
    )
    
    (ok true)
  )
)

(define-public (submit-review
    (paper-id uint)
    (score uint)
    (comments (string-ascii 1000))
    (recommendation (string-ascii 20))
    (is-anonymous bool)
  )
  (let (
    (reviewer tx-sender)
    (review-id (increment-review-counter))
    (timestamp stacks-block-height)
  )
    ;; Validate input
    (asserts! (and (>= score MIN_SCORE) (<= score MAX_SCORE)) ERR_INVALID_SCORE)
    (asserts! (> (len comments) u0) ERR_INVALID_INPUT)
    
    ;; Check if reviewer is assigned and hasn't submitted yet
    (asserts! (is-reviewer-assigned paper-id reviewer) ERR_UNAUTHORIZED)
    (asserts! (not (has-reviewer-submitted paper-id reviewer)) ERR_ALREADY_REVIEWED)
    
    ;; Check if review period is still open
    (let (
      (assignment (unwrap! (map-get? ReviewerAssignments { paper-id: paper-id, reviewer: reviewer }) ERR_UNAUTHORIZED))
    )
      (asserts! (<= timestamp (get deadline assignment)) ERR_REVIEW_CLOSED)
    )
    
    ;; Submit the review
    (map-set Reviews
      { review-id: review-id }
      {
        paper-id: paper-id,
        reviewer: reviewer,
        score: score,
        comments: comments,
        recommendation: recommendation,
        timestamp: timestamp,
        quality-score: u0,
        is-anonymous: is-anonymous
      }
    )
    
    ;; Mark assignment as completed
    (match (map-get? ReviewerAssignments { paper-id: paper-id, reviewer: reviewer })
      assignment
        (map-set ReviewerAssignments
          { paper-id: paper-id, reviewer: reviewer }
          (merge assignment {
            is-completed: true,
            review-id: (some review-id)
          })
        )
      false
    )
    
    ;; Update paper reviews
    (match (map-get? PaperReviews { paper-id: paper-id })
      paper-review
        (let (
          (current-reviews (get review-ids paper-review))
          (updated-reviews (unwrap! (as-max-len? (append current-reviews review-id) u10) ERR_INVALID_INPUT))
          (new-total (+ (get total-reviews paper-review) u1))
        )
          (map-set PaperReviews
            { paper-id: paper-id }
            (merge paper-review {
              review-ids: updated-reviews,
              total-reviews: new-total,
              status: (if (>= new-total REQUIRED_REVIEWS) STATUS_REVIEWED STATUS_IN_REVIEW)
            })
          )
        )
      false
    )
    
    ;; Update total reviews counter
    (var-set total-reviews (+ (var-get total-reviews) u1))
    
    (ok review-id)
  )
)

(define-public (rate-review-quality
    (review-id uint)
    (helpfulness uint)
    (accuracy uint)
    (timeliness uint)
  )
  (let (
    (review-data (unwrap! (map-get? Reviews { review-id: review-id }) ERR_REVIEW_NOT_FOUND))
    (reviewer (get reviewer review-data))
  )
    ;; Validate scores
    (asserts! (and (<= helpfulness MAX_SCORE) (<= accuracy MAX_SCORE) (<= timeliness MAX_SCORE)) ERR_INVALID_SCORE)
    (asserts! (and (>= helpfulness MIN_SCORE) (>= accuracy MIN_SCORE) (>= timeliness MIN_SCORE)) ERR_INVALID_SCORE)
    
    ;; Calculate quality score
    (let (
      (quality-score (calculate-review-quality review-id helpfulness accuracy timeliness))
    )
      ;; Update review with quality score
      (map-set Reviews
        { review-id: review-id }
        (merge review-data { quality-score: quality-score })
      )
      
      ;; Update reviewer statistics
      (update-reviewer-stats reviewer quality-score)
      
      (ok quality-score)
    )
  )
)

(define-public (finalize-paper-review (paper-id uint))
  (match (map-get? PaperReviews { paper-id: paper-id })
    paper-review
      (let (
        (review-ids (get review-ids paper-review))
        (current-total-reviews (get total-reviews paper-review))
      )
        ;; Check if we have sufficient reviews
        (asserts! (>= current-total-reviews REQUIRED_REVIEWS) ERR_INSUFFICIENT_REVIEWS)
        
        ;; Calculate average score
        (let (
          (scores (map get-review-score review-ids))
          (average-score (calculate-average-score scores))
          (final-status (if (>= average-score QUALITY_THRESHOLD) STATUS_ACCEPTED STATUS_REJECTED))
        )
          ;; Update paper review status
          (map-set PaperReviews
            { paper-id: paper-id }
            (merge paper-review {
              average-score: average-score,
              status: final-status
            })
          )
          
          (ok true)
        )
      )
    ERR_PAPER_NOT_FOUND
  )
)

;; Helper function for mapping
(define-private (get-review-score (review-id uint))
  (match (map-get? Reviews { review-id: review-id })
    review-data (get score review-data)
    u0
  )
)

;; Read-only functions
(define-read-only (get-review (review-id uint))
  (map-get? Reviews { review-id: review-id })
)

(define-read-only (get-paper-reviews (paper-id uint))
  (map-get? PaperReviews { paper-id: paper-id })
)

(define-read-only (get-reviewer-info (reviewer principal))
  (map-get? Reviewers { reviewer: reviewer })
)

(define-read-only (get-reviewer-assignment (paper-id uint) (reviewer principal))
  (map-get? ReviewerAssignments { paper-id: paper-id, reviewer: reviewer })
)

(define-read-only (get-review-quality (review-id uint))
  (map-get? ReviewQualities { review-id: review-id })
)

(define-read-only (get-paper-reviewer-pool (paper-id uint))
  (map-get? PaperReviewerPool { paper-id: paper-id })
)

(define-read-only (get-total-reviews)
  (var-get total-reviews)
)

(define-read-only (get-reviewer-counter)
  (var-get reviewer-counter)
)

(define-read-only (is-review-complete (paper-id uint))
  (match (map-get? PaperReviews { paper-id: paper-id })
    paper-review
      (>= (get total-reviews paper-review) REQUIRED_REVIEWS)
    false
  )
)

