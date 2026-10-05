use asefile::AsepriteFile;
use gpui::RenderImage;
use image::{Frame as ImageFrame, RgbaImage};
use smallvec::SmallVec;
use std::{
    sync::Arc,
    time::{Duration, Instant},
};

const ART: &[u8] = include_bytes!("../loading.aseprite");

const HOLDS: [u32; 25] = [
    200, 90, 90, 90, 90, 90, 90, 90, 90, 90, 90, 500, 500, 90, 90, 90, 90, 90, 90, 90, 90, 90,
    90, 90, 90,
];

pub(crate) struct LoadingAnimation {
    frames: Vec<Arc<RenderImage>>,
    size: (u32, u32),
    started: Instant,
}

impl LoadingAnimation {
    pub(crate) fn load() -> Self {
        let file = AsepriteFile::read(ART).expect("the loading animation is not an aseprite file");
        let (width, height) = file.size();
        let frames: Vec<Arc<RenderImage>> = (0..file.num_frames())
            .map(|index| {
                let drawn = file.frame(index).image();
                let (frame_width, frame_height) = drawn.dimensions();
                let pixels = RgbaImage::from_raw(frame_width, frame_height, drawn.into_raw())
                    .expect("a frame of the loading animation is not a whole image");

                Arc::new(RenderImage::new(SmallVec::from_elem(
                    ImageFrame::new(pixels),
                    1,
                )))
            })
            .collect();

        assert!(!frames.is_empty(), "the loading animation has no frames");
        Self {
            frames,
            size: (width as u32, height as u32),
            started: Instant::now(),
        }
    }

    pub(crate) fn size(&self) -> (u32, u32) {
        self.size
    }

    pub(crate) fn frame(&self) -> &Arc<RenderImage> {
        &self.frames[at(self.started.elapsed(), &HOLDS)]
    }
}

fn at(elapsed: Duration, holds: &[u32]) -> usize {
    let total = holds.iter().map(|hold| u64::from(*hold)).sum::<u64>();

    if total == 0 {
        return 0;
    }
    let mut left = (elapsed.as_millis() as u64) % total;
    for (index, hold) in holds.iter().enumerate() {
        if left < u64::from(*hold) {
            return index;
        }
        left -= u64::from(*hold);
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    const HEADER: usize = 128;

    fn frame_size(offset: usize) -> usize {
        u32::from_le_bytes([
            ART[offset],
            ART[offset + 1],
            ART[offset + 2],
            ART[offset + 3],
        ]) as usize
    }

    #[test]
    fn every_frame_of_the_animation_comes_out_of_the_file() {
        let art = AsepriteFile::read(ART).expect("the loading animation is not an aseprite file");
        let (width, height) = art.size();

        assert_eq!((width, height), (64, 64), "the animation is not the size it was drawn at");
        assert!(art.num_frames() >= 2, "the animation has {} frame(s)", art.num_frames());
        assert_eq!(
            art.num_frames() as usize,
            HOLDS.len(),
            "the animation holds {} frames and the timing covers {}",
            art.num_frames(),
            HOLDS.len()
        );
        let painted = (0..art.num_frames())
            .map(|index| art.frame(index).image().pixels().filter(|pixel| pixel[3] > 0).count())
            .collect::<Vec<usize>>();
        let drawn = painted.iter().filter(|count| **count > 0).count();

        assert!(
            drawn >= 2,
            "only {drawn} of {} frames carry any drawing",
            art.num_frames()
        );
        let loaded = LoadingAnimation::load();
        assert_eq!(loaded.size(), (64, 64));
        assert_eq!(loaded.frames.len() as u32, art.num_frames());
    }

    #[test]
    fn no_frame_of_the_animation_carries_a_duration() {
        let frames = u16::from_le_bytes([ART[6], ART[7]]) as usize;

        let mut offset = HEADER;
        for index in 0..frames {
            let magic = u16::from_le_bytes([ART[offset + 4], ART[offset + 5]]);
            let duration = u16::from_le_bytes([ART[offset + 6], ART[offset + 7]]);

            assert_eq!(magic, 0xf1fa, "frame {index} is not an aseprite frame");
            assert_eq!(duration, 0, "frame {index} carries a duration of {duration} ms");
            offset += frame_size(offset);
        }
        assert_eq!(offset, ART.len(), "the frames do not add up to the file");
    }

    #[test]
    fn the_animation_holds_each_frame_for_as_long_as_aseprite_does() {
        assert_eq!(at(Duration::ZERO, &HOLDS), 0);
        assert_eq!(at(Duration::from_millis(199), &HOLDS), 0, "the first frame let go early");
        assert_eq!(at(Duration::from_millis(200), &HOLDS), 1);
        assert_eq!(at(Duration::from_millis(200 + 90 * 10), &HOLDS), 11, "the peak frame is not where it is held");
        assert_eq!(at(Duration::from_millis(200 + 90 * 10 + 499), &HOLDS), 11);
        assert_eq!(at(Duration::from_millis(200 + 90 * 10 + 500), &HOLDS), 12);
        assert_eq!(at(Duration::from_millis(3180 - 1), &HOLDS), 24, "the loop is not a full loop long");
        assert_eq!(at(Duration::from_millis(3180), &HOLDS), 0, "the loop did not start again");
        assert_eq!(at(Duration::from_millis(3180 + 250), &HOLDS), 1);
        assert_eq!(at(Duration::from_secs(600), &HOLDS), at(Duration::from_secs(600 + 3180), &HOLDS));
    }
}
