local Types = {}

export type StemData = {
	Volume: number,
	SoundId: string,
}

export type SongData = {
	Title: string,
	Artist: string,
	Stems: { [string]: StemData },
	StartingBPM: number,
	StartingBeatsPerMeasure: number,
	IntendedPlaybackSpeed: number,
}

return Types
