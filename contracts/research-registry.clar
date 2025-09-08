;; Research Registry Contract
;; Smart contract for registering research papers with immutable timestamps

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_PAPER_NOT_FOUND (err u101))
(define-constant ERR_PAPER_EXISTS (err u102))
(define-constant ERR_INVALID_INPUT (err u103))
(define-constant ERR_INVALID_AUTHOR (err u104))
(define-constant ERR_VERSION_EXISTS (err u105))

;; Data Variables
(define-data-var paper-counter uint u0)
(define-data-var total-papers uint u0)

;; Data Maps
(define-map Papers
  { paper-id: uint }
  {
    title: (string-ascii 200),
    abstract: (string-ascii 1000),
    authors: (list 10 principal),
    paper-hash: (buff 32),
    timestamp: uint,
    version: uint,
    status: (string-ascii 20),
    category: (string-ascii 50),
    keywords: (list 10 (string-ascii 30)),
    doi: (string-ascii 100)
  }
)

(define-map PaperVersions
  { paper-id: uint, version: uint }
  {
    paper-hash: (buff 32),
    timestamp: uint,
    changes: (string-ascii 500)
  }
)

(define-map AuthorPapers
  { author: principal }
  { paper-ids: (list 100 uint) }
)

(define-map PaperAuthors
  { paper-id: uint }
  { authors: (list 10 principal) }
)

(define-map CategoryPapers
  { category: (string-ascii 50) }
  { paper-ids: (list 1000 uint) }
)

;; Private Functions
(define-private (increment-paper-counter)
  (let ((current-count (var-get paper-counter)))
    (var-set paper-counter (+ current-count u1))
    (+ current-count u1)
  )
)

(define-private (generate-doi (paper-id uint))
  (concat "10.5555/" (int-to-ascii paper-id))
)

(define-private (is-valid-author (author principal) (authors (list 10 principal)))
  (is-some (index-of authors author))
)

(define-private (add-to-author-papers (author principal) (paper-id uint))
  (let (
    (current-papers (default-to (list) (get paper-ids (map-get? AuthorPapers { author: author }))))
    (updated-papers (unwrap! (as-max-len? (append current-papers paper-id) u100) false))
  )
    (map-set AuthorPapers { author: author } { paper-ids: updated-papers })
    true
  )
)

(define-private (add-to-category-papers (category (string-ascii 50)) (paper-id uint))
  (let (
    (current-papers (default-to (list) (get paper-ids (map-get? CategoryPapers { category: category }))))
    (updated-papers (unwrap! (as-max-len? (append current-papers paper-id) u1000) false))
  )
    (map-set CategoryPapers { category: category } { paper-ids: updated-papers })
    true
  )
)

;; Public Functions
(define-public (register-paper
    (title (string-ascii 200))
    (abstract (string-ascii 1000))
    (authors (list 10 principal))
    (paper-hash (buff 32))
    (category (string-ascii 50))
    (keywords (list 10 (string-ascii 30)))
  )
  (let (
    (paper-id (increment-paper-counter))
    (timestamp stacks-block-height)
    (doi (generate-doi paper-id))
  )
    ;; Validate inputs
    (asserts! (> (len title) u0) ERR_INVALID_INPUT)
    (asserts! (> (len abstract) u0) ERR_INVALID_INPUT)
    (asserts! (> (len authors) u0) ERR_INVALID_INPUT)
    (asserts! (> (len paper-hash) u0) ERR_INVALID_INPUT)
    
    ;; Check if caller is one of the authors
    (asserts! (is-valid-author tx-sender authors) ERR_UNAUTHORIZED)
    
    ;; Register the paper
    (map-set Papers
      { paper-id: paper-id }
      {
        title: title,
        abstract: abstract,
        authors: authors,
        paper-hash: paper-hash,
        timestamp: timestamp,
        version: u1,
        status: "registered",
        category: category,
        keywords: keywords,
        doi: doi
      }
    )
    
    ;; Set initial version
    (map-set PaperVersions
      { paper-id: paper-id, version: u1 }
      {
        paper-hash: paper-hash,
        timestamp: timestamp,
        changes: "Initial registration"
      }
    )
    
    ;; Update author mappings
    (map-set PaperAuthors { paper-id: paper-id } { authors: authors })
    
    ;; Add to first author's paper list (simplified)
    (match (element-at authors u0)
      author (add-to-author-papers author paper-id)
      false
    )
    
    ;; Add to category
    (add-to-category-papers category paper-id)
    
    ;; Increment total papers
    (var-set total-papers (+ (var-get total-papers) u1))
    
    (ok paper-id)
  )
)


(define-public (update-paper
    (paper-id uint)
    (paper-hash (buff 32))
    (changes (string-ascii 500))
  )
  (let (
    (paper-data (unwrap! (map-get? Papers { paper-id: paper-id }) ERR_PAPER_NOT_FOUND))
    (authors (get authors paper-data))
    (current-version (get version paper-data))
    (new-version (+ current-version u1))
  )
    ;; Validate caller is an author
    (asserts! (is-valid-author tx-sender authors) ERR_UNAUTHORIZED)
    
    ;; Update paper version
    (map-set Papers
      { paper-id: paper-id }
      (merge paper-data {
        paper-hash: paper-hash,
        version: new-version,
        timestamp: stacks-block-height
      })
    )
    
    ;; Add version record
    (map-set PaperVersions
      { paper-id: paper-id, version: new-version }
      {
        paper-hash: paper-hash,
        timestamp: stacks-block-height,
        changes: changes
      }
    )
    
    (ok new-version)
  )
)

(define-public (update-paper-status
    (paper-id uint)
    (new-status (string-ascii 20))
  )
  (let (
    (paper-data (unwrap! (map-get? Papers { paper-id: paper-id }) ERR_PAPER_NOT_FOUND))
    (authors (get authors paper-data))
  )
    ;; Validate caller is an author
    (asserts! (is-valid-author tx-sender authors) ERR_UNAUTHORIZED)
    
    ;; Update status
    (map-set Papers
      { paper-id: paper-id }
      (merge paper-data { status: new-status })
    )
    
    (ok true)
  )
)

;; Read-only functions
(define-read-only (get-paper (paper-id uint))
  (map-get? Papers { paper-id: paper-id })
)

(define-read-only (get-paper-version (paper-id uint) (version uint))
  (map-get? PaperVersions { paper-id: paper-id, version: version })
)

(define-read-only (get-author-papers (author principal))
  (map-get? AuthorPapers { author: author })
)

(define-read-only (get-category-papers (category (string-ascii 50)))
  (map-get? CategoryPapers { category: category })
)

(define-read-only (get-paper-authors (paper-id uint))
  (map-get? PaperAuthors { paper-id: paper-id })
)

(define-read-only (get-total-papers)
  (var-get total-papers)
)

(define-read-only (get-paper-counter)
  (var-get paper-counter)
)

(define-read-only (verify-author (paper-id uint) (author principal))
  (match (map-get? Papers { paper-id: paper-id })
    paper-data (is-valid-author author (get authors paper-data))
    false
  )
)

(define-read-only (get-paper-hash (paper-id uint))
  (match (map-get? Papers { paper-id: paper-id })
    paper-data (some (get paper-hash paper-data))
    none
  )
)

