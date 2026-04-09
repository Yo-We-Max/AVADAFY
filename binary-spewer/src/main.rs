use std::io::{self, Write};
use std::time::Duration;

use crossterm::{
    cursor,
    event::{self, Event, KeyCode, KeyEvent},
    execute,
    style::{Color, Print, SetForegroundColor},
    terminal::{self, ClearType},
};
use rand::Rng;

/// Each column tracks its current "drop" position and speed.
struct Column {
    /// Current row position of the leading character.
    head: f64,
    /// Previous integer head row (for multi-row erasure).
    prev_head_row: i32,
    /// Rows to advance per tick.
    speed: f64,
    /// Length of the bright trail behind the head.
    trail_len: usize,
}

impl Column {
    fn new(rows: u16, rng: &mut impl Rng) -> Self {
        let head = rng.gen_range(-(rows as f64)..0.0);
        Self {
            head,
            prev_head_row: head as i32,
            speed: rng.gen_range(0.3..1.5),
            trail_len: rng.gen_range(4..16),
        }
    }

    fn reset(&mut self, rows: u16, rng: &mut impl Rng) {
        self.head = rng.gen_range(-(rows as f64 * 0.5)..0.0);
        self.prev_head_row = self.head as i32;
        self.speed = rng.gen_range(0.3..1.5);
        self.trail_len = rng.gen_range(4..16);
    }
}

fn main() -> io::Result<()> {
    let mut stdout = io::stdout();

    // Enter raw / alternate-screen mode
    terminal::enable_raw_mode()?;
    execute!(
        stdout,
        terminal::EnterAlternateScreen,
        cursor::Hide,
        terminal::Clear(ClearType::All)
    )?;

    let result = run(&mut stdout);

    // Restore terminal on exit
    execute!(stdout, cursor::Show, terminal::LeaveAlternateScreen)?;
    terminal::disable_raw_mode()?;

    result
}

fn run(stdout: &mut io::Stdout) -> io::Result<()> {
    let mut rng = rand::thread_rng();

    let (mut cols, mut rows) = terminal::size()?;

    // Initialise one column tracker per terminal column
    let mut columns: Vec<Column> = (0..cols).map(|_| Column::new(rows, &mut rng)).collect();

    loop {
        // Handle resize & quit
        if event::poll(Duration::from_millis(30))? {
            match event::read()? {
                Event::Key(KeyEvent {
                    code: KeyCode::Char('q'),
                    ..
                })
                | Event::Key(KeyEvent {
                    code: KeyCode::Esc, ..
                }) => {
                    break;
                }
                Event::Key(KeyEvent {
                    code: KeyCode::Char('c'),
                    modifiers,
                    ..
                }) if modifiers.contains(event::KeyModifiers::CONTROL) => {
                    break;
                }
                Event::Resize(new_cols, new_rows) => {
                    cols = new_cols;
                    rows = new_rows;
                    columns.resize_with(cols as usize, || Column::new(rows, &mut rng));
                    execute!(stdout, terminal::Clear(ClearType::All))?;
                }
                _ => {}
            }
        }

        // Draw each column
        for (x, col) in columns.iter_mut().enumerate() {
            let head_row = col.head as i32;

            // Draw the bright head character
            if head_row >= 0 && head_row < rows as i32 {
                let ch = if rng.gen_bool(0.5) { '1' } else { '0' };
                execute!(
                    stdout,
                    cursor::MoveTo(x as u16, head_row as u16),
                    SetForegroundColor(Color::White),
                    Print(ch)
                )?;
            }

            // Draw trailing characters in green shades
            for t in 1..=col.trail_len {
                let trail_row = head_row - t as i32;
                if trail_row >= 0 && trail_row < rows as i32 {
                    let ch = if rng.gen_bool(0.5) { '1' } else { '0' };
                    // Fade from bright green to dark green
                    let brightness = 255 - ((t as u16 * 200) / col.trail_len as u16).min(200);
                    execute!(
                        stdout,
                        cursor::MoveTo(x as u16, trail_row as u16),
                        SetForegroundColor(Color::Rgb {
                            r: 0,
                            g: brightness as u8,
                            b: 0,
                        }),
                        Print(ch)
                    )?;
                }
            }

            // Erase all rows past the trail that may have been skipped
            let new_erase = head_row - col.trail_len as i32 - 1;
            let old_erase = col.prev_head_row - col.trail_len as i32 - 1;
            let erase_start = old_erase.max(0);
            let erase_end = new_erase.min(rows as i32 - 1);
            for er in erase_start..=erase_end {
                execute!(stdout, cursor::MoveTo(x as u16, er as u16), Print(' '))?;
            }

            // Advance the column
            col.prev_head_row = head_row;
            col.head += col.speed;

            // Reset when fully off-screen
            if (col.head as i32 - col.trail_len as i32) > rows as i32 {
                col.reset(rows, &mut rng);
            }
        }

        stdout.flush()?;
    }

    Ok(())
}
