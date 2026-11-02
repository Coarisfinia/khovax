# Audio: sources, import and checks

How to obtain and prepare a sound. How the game loads and plays it isn't here: see #2014 and the
code. Read the parent `SKILL.md` first for the license rules and `SOURCE.md`.

## Sources

Checked on 2026-11-02 from each publisher's own pages (#1994). Treat these as where to start: the
exact file's own page still decides. None of this is legal advice.

| Source | What its pages say | Use it like this |
|---|---|---|
| [Kenney](https://kenney.nl/assets/interface-sounds) | Its asset page marks the pack CC0; its [support page](https://kenney.nl/support) says all assets are CC0, attribution not required, and points to the included license file | First choice for menu feedback. Take the files you use, and read the license file in the download |
| [Wikimedia Commons](https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia) | No blanket license: each file page gives author and license; the Foundation gives no warranty that they're right, and tells reusers to verify | Natural and animal recordings. CC0 or CC BY files only: ShareAlike and others aren't allowed here |
| [Free Sounds Library](https://www.freesoundslibrary.com/about-us/) | CC BY 4.0, and credit "Downloaded from www.freesoundslibrary.com"; "our team owns the copyrights"; use "in your multimedia projects" | Candidates only, each needing independent provenance or the owner's decision; see below |
| [Freesound.org](https://freesound.org/help/faq/) | Each sound has its own license: CC0, CC BY or CC BY-NC, plus the retired Sampling+ on old uploads | Filter to CC0 or CC BY and read the file's page; CC BY-NC and Sampling+ aren't allowed here |

**Free Sounds Library and Freesound.org are different services** with different terms. Name the
right one in `SOURCE.md`.

**Not verified:**

- **Free Sounds Library's ownership claim:** nothing on its pages shows who recorded a given file
  or how the team came to own it, so its CC BY rests on its word. Its pages also ask for less credit
  than CC BY ("if your business is not online you don't need to specify"), and the ones checked
  never mention redistributing the file; follow CC BY.
- **[The distant wolf howl](https://www.freesoundslibrary.com/distant-wolf-howling-at-night-sound-effect/):**
  its own page and the zip's `Read.txt` state CC BY 4.0, but they name no recordist, and the page
  was published only on 2026-10-31. It is **not cleared**, like every file from this site until the ownership
  claim above is settled.
- **Kenney's license file:** not opened for this assessment.

## Choosing a file

- **One file's license, per file.** Commons and Freesound uploads can be someone else's work: look
  for a stated origin, and be wary of a clip that sounds lifted from a film or a game.
- **Download the highest-quality version** the page offers, lossless if there is one, and hash it.
  Commit only the file the game uses.
- **A remix carries its sources' terms**: if the page names source sounds, check those too.

## Preparing it

- **Change as little as you can**, and write each change and its command into `Modifications`. CC
  BY requires noting them; CC0 doesn't, but the next reader wants to know. Hash the file as
  downloaded, before any change.
- **Format:** the game's music is Ogg Vorbis (`assets/exploration-theme/`); Godot also imports WAV
  and MP3. Re-encoding one lossy format into another loses quality, so a lossy source stays as it
  is unless there's a reason. `.gitattributes` marks only `.ogg` and `.wav` as binary, so a first
  MP3 adds its line.
- **Size:** every file ships in the game's builds, the web one included. From a lossless source, cut
  leading and trailing silence, and use mono for a short effect that has no use for stereo. From a
  lossy one, trimming or going mono means re-encoding, so do it only if the saving is worth the loss.
- **Trim** at silence or, except on a loop, with a short fade (`afade`), so no click is left at the
  edge.
- **Loops:** set them in the file's `.import` (`loop=true`, as the exploration theme does, plus
  `loop_offset`; a WAV's is `edit/loop_mode`), not by doubling the audio. Ending and starting at the same level and phase avoids
  a seam.

## Checks

Measure every file, and put the numbers in the pull request:

```sh
ffprobe -v error -show_entries format=format_name,duration,bit_rate:stream=codec_name,sample_rate,channels -of default=nw=1 "$F"
ffmpeg -hide_banner -nostats -i "$F" -af "volumedetect,silencedetect=n=-50dB:d=0.2,loudnorm=print_format=summary" -f null - 2>&1 |
  grep -E "max_volume|mean_volume|silence_|Input (Integrated|True Peak|LRA)"
ffmpeg -hide_banner -v error -y -i "$F" -lavfi showspectrumpic=s=800x300:legend=0 "$SCRATCH/spectrum.png"
```

`$SCRATCH` is any folder outside the repository: a picture left in the pack would be imported, and
fail the unused-asset check if committed.

- **Clipping:** a true peak at or above 0 dBTP, or flat-topped peaks. Prefer another file to one
  that clips.
- **Level:** compare integrated loudness with the sounds it plays beside, so that nothing jumps out.
  On a very short clip it reads `-inf` (0.2 s did): compare `max_volume` and `mean_volume` there.
- **Noise:** the spectrum shows hum, hiss and a cut-off top end, typical of a poor transcode.

**An agent can't hear.** The numbers don't catch speech in the background, a seam that sounds
wrong, or a sound that doesn't fit. Those need a person: link the file in the pull request, say that
nobody has listened to it yet, and ask the owner to listen for clipping, unwanted speech or noise,
loop seams and balance. Never report a file as "listened to" because it measured well.
