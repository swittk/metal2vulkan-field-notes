use std::env;
use std::time::{Duration, Instant};
use std::thread;

use metal2vulkan::metal::{PixelFormat, TextureUsage};
use metal2vulkan_runtime::{
    BlitOption, ClearColor, CommandBufferStatus, Device, IoSurfacePlane, LoadAction, Origin,
    RenderPassDescriptor, ResourceOptions, Size, StoreAction, TextureDescriptor,
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let duration: u64 = env::var("BENCH_SECS").unwrap_or("6".to_owned()).parse()?;
    let passes: u32 = env::var("BENCH_PASSES").unwrap_or("4".to_owned()).parse()?;
    let resolution = env::var("BENCH_RESOLUTION").unwrap_or("1920x1080".to_owned());
    let dims: Vec<u64> = resolution.split('x').map(str::parse).collect::<Result<_, _>>()?;
    if dims.len() != 2 || duration < 2 || duration > 120 || passes < 1 || passes > 96 {
        return Err("Invalid duration, passes or dimensions".into());
    }
    let (width, height) = (dims[0], dims[1]);
    if width > 4096 || height > 2160 || width == 0 || height == 0 {
        return Err("Invalid surface dimension".into());
    }
    let hz = 30u64;
    let device = Device::system_default()?;
    println!("DEVICE {}", device.name());
    let row = width * 4 + 32;
    let offset = 256u64;
    let length = offset + row * height + 256;
    let bytes = vec![0xa5u8; length as usize];
    let backing = device.new_buffer_with_bytes(&bytes, ResourceOptions::private())?;
    let mut desc = TextureDescriptor::texture_2d(PixelFormat::RGBA8Unorm, width, height, false);
    desc.usage = TextureUsage::SHADER_READ | TextureUsage::RENDER_TARGET;
    desc.resource_options = ResourceOptions::shared();
    let plane = IoSurfacePlane::new(offset, row, true);
    let target = backing.new_texture_with_iosurface_plane(&desc, plane)?;
    let alias = backing.new_texture_with_iosurface_plane(&desc, plane)?;
    let queue = device.new_command_queue()?;
    // Only a small pixel strip is copied to CPU to check changing output every frame.
    let check_width = 16u64.min(width);
    let check_height = 16u64.min(height);
    let check_row = check_width * 4;
    let check_size = check_row * check_height;
    let readback = device.new_buffer(check_size, ResourceOptions::shared())?;
    let colors: [(ClearColor, [u8; 4]); 3] = [
        (ClearColor::new(1.0, 0.0, 0.0, 1.0), [255, 0, 0, 255]),
        (ClearColor::new(0.0, 1.0, 0.0, 1.0), [0, 255, 0, 255]),
        (ClearColor::new(0.0, 0.0, 1.0, 1.0), [0, 0, 255, 255]),
    ];
    // Exclude initial surface/pipeline creation and first render from the timed period.
    let mut waits = Vec::new();
    let mut timed_epoch: Option<Instant> = None;
    let mut total_hash = 0u64;
    let frames = duration * hz;
    for iteration in 0..frames + 15 {
        let warmup = iteration < 15;
        let frame = iteration.saturating_sub(15);
        if !warmup && frame == 0 {
            timed_epoch = Some(Instant::now());
            println!("BENCH_START secs={} passes={} resolution={} hz={}", duration, passes, resolution, hz);
            std::io::Write::flush(&mut std::io::stdout())?;
        }
        if !warmup {
            let deadline = timed_epoch.unwrap() + Duration::from_secs_f64(frame as f64 / hz as f64);
            if let Some(remaining) = deadline.checked_duration_since(Instant::now()) {
                thread::sleep(remaining);
            }
        }
        let (color, expected) = &colors[(iteration as usize) % colors.len()];
        let cb = queue.command_buffer()?;
        for pass in 0..passes {
            let mut rp = RenderPassDescriptor::new();
            let attachment = &mut rp.color_attachments[0];
            attachment.texture = Some(target.clone());
            attachment.load_action = if pass == 0 { LoadAction::Clear } else { LoadAction::Load };
            attachment.store_action = StoreAction::Store;
            attachment.clear_color = *color;
            cb.render_command_encoder(&rp)?.end_encoding()?;
        }
        let mut blit = cb.blit_command_encoder()?;
        blit.copy_from_texture_to_buffer(
            &alias, 0, 0, Origin::new(0, 0, 0),
            Size::new(check_width, check_height, 1),
            &readback, 0, check_row, check_size, BlitOption::None,
        )?;
        blit.end_encoding()?;
        let started = Instant::now();
        cb.commit()?;
        cb.wait_until_completed_for(Duration::from_secs(15))
            .map_err(|_| "Wait timed out")?;
        if cb.status() != CommandBufferStatus::Completed {
            return Err(format!("GPU work failed: {:?}: {:?}", cb.status(), cb.error()).into());
        }
        let elapsed = started.elapsed().as_secs_f64() * 1000.0;
        let contents = readback.contents().ok_or("Readback buffer unavailable")?;
        // Every sampled texel must be the new color, without stale content.
        let actual = unsafe { std::slice::from_raw_parts(contents.as_ptr(), check_size as usize) };
        if actual.chunks_exact(4).any(|chunk| chunk != *expected) {
            return Err(format!("Incorrect color frame {} after {} passes, first texel {:?}, expected {:?}",
                iteration, passes, &actual[0..4], expected).into());
        }
        total_hash = total_hash.wrapping_mul(131).wrapping_add(actual[0] as u64 + 3*actual[1] as u64 + 5*actual[2] as u64);
        if !warmup {
            waits.push(elapsed);
        }
    }
    waits.sort_by(|a,b|a.partial_cmp(b).unwrap());
    let len=waits.len();
    let sum:f64=waits.iter().sum();
    println!("BENCH_PASS frames={} max_wait_ms={:.3} mean_wait_ms={:.3} p50_ms={:.3} p95_ms={:.3} p99_ms={:.3} hash={} passes={} size={}",
        len, waits[len-1], sum/len as f64, waits[len/2], waits[(len*95/100).min(len-1)], waits[(len*99/100).min(len-1)], total_hash, passes, resolution);
    Ok(())
}
