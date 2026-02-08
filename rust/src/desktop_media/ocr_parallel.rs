const OCR_BASE_PAGE_WORKERS: usize = 2;
const OCR_MID_PAGE_WORKERS: usize = 3;
const OCR_MAX_PAGE_WORKERS: usize = 4;
const OCR_MID_PAGE_THRESHOLD: usize = 12;
const OCR_MAX_PAGE_THRESHOLD: usize = 32;

pub(super) fn choose_ocr_page_worker_count(
    pages_with_images: usize,
    available_parallelism: usize,
) -> usize {
    if pages_with_images <= 1 {
        return 1;
    }

    let cpu_cap = available_parallelism.clamp(1, OCR_MAX_PAGE_WORKERS);
    let page_cap = if pages_with_images >= OCR_MAX_PAGE_THRESHOLD {
        OCR_MAX_PAGE_WORKERS
    } else if pages_with_images >= OCR_MID_PAGE_THRESHOLD {
        OCR_MID_PAGE_WORKERS
    } else {
        OCR_BASE_PAGE_WORKERS
    };

    cpu_cap.min(page_cap).min(pages_with_images)
}
