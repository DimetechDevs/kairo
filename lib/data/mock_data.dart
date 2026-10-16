import 'package:flutter/material.dart';

import 'models.dart';

/// Sample catalogue used until the AniList service is connected.
/// Ids are intended to match AniList media ids; verify them when the service is connected.
const mockCatalogue = <Anime>[
  Anime(
    id: 154587,
    title: "Frieren: Beyond Journey's End",
    shortTitle: 'Frieren',
    nativeTitle: 'Sousou no Frieren',
    year: 2023,
    format: 'TV',
    episodes: 28,
    status: 'Finished',
    genres: ['Adventure', 'Drama', 'Fantasy'],
    synopsis:
        "After the hero's party defeats the Demon King, the elf mage Frieren goes her own way. Decades later, "
        'outliving the friends she travelled with, she sets out on a new journey to understand the people she '
        'barely got to know, and what their time together meant.',
    palette: [Color(0xFF5B3FD1), Color(0xFF1F1A3D)],
  ),
  Anime(
    id: 171018,
    title: 'Dandadan',
    shortTitle: 'Dandadan',
    year: 2024,
    format: 'TV',
    episodes: 12,
    status: 'Finished',
    genres: ['Action', 'Comedy', 'Sci-Fi'],
    synopsis: 'A girl who believes in ghosts and a boy who believes in aliens set out to prove each other wrong, '
        'and run into both.',
    palette: [Color(0xFFE0567A), Color(0xFF2E1A33)],
  ),
  Anime(
    id: 151807,
    title: 'Solo Leveling',
    shortTitle: 'Solo Leveling',
    year: 2024,
    format: 'TV',
    episodes: 12,
    status: 'Finished',
    genres: ['Action', 'Fantasy'],
    synopsis: 'The weakest hunter in a world of monster-filled dungeons gains a mysterious power that lets him grow stronger.',
    palette: [Color(0xFF2C8FC0), Color(0xFF16213A)],
  ),
  Anime(
    id: 163132,
    title: 'Kaiju No. 8',
    shortTitle: 'Kaiju No. 8',
    year: 2024,
    format: 'TV',
    episodes: 12,
    status: 'Finished',
    genres: ['Action', 'Sci-Fi'],
    synopsis: 'A man who cleans up after monster attacks suddenly becomes a monster himself.',
    palette: [Color(0xFF3FB37F), Color(0xFF14302A)],
  ),
  Anime(
    id: 161645,
    title: 'The Apothecary Diaries',
    shortTitle: 'Apothecary Diaries',
    year: 2023,
    format: 'TV',
    episodes: 24,
    status: 'Finished',
    genres: ['Drama', 'Mystery'],
    synopsis: "A young apothecary working in the imperial palace uses her knowledge to solve the court's mysteries.",
    palette: [Color(0xFFD99A3B), Color(0xFF3A2716)],
  ),
  Anime(
    id: 140960,
    title: 'Spy x Family',
    shortTitle: 'Spy x Family',
    year: 2022,
    format: 'TV',
    episodes: 25,
    status: 'Finished',
    genres: ['Action', 'Comedy'],
    synopsis: 'A spy builds a fake family for a mission, without knowing his wife is an assassin and his daughter reads minds.',
    palette: [Color(0xFFF08FB0), Color(0xFF3A1F33)],
  ),
  Anime(
    id: 137822,
    title: 'Blue Lock',
    shortTitle: 'Blue Lock',
    year: 2022,
    format: 'TV',
    episodes: 24,
    status: 'Finished',
    genres: ['Sports'],
    synopsis: "Hundreds of young strikers compete in a training facility to become Japan's next great forward.",
    palette: [Color(0xFF3D6BE0), Color(0xFF141E3D)],
  ),
  Anime(
    id: 150672,
    title: 'Oshi no Ko',
    shortTitle: 'Oshi no Ko',
    year: 2023,
    format: 'TV',
    episodes: 11,
    status: 'Finished',
    genres: ['Drama', 'Mystery'],
    synopsis: 'A doctor is reborn as the child of the idol he admired, and is pulled into the dark side of show business.',
    palette: [Color(0xFFB65BE0), Color(0xFF2A163A)],
  ),
  Anime(
    id: 20464,
    title: 'Haikyu!!',
    shortTitle: 'Haikyu!!',
    year: 2014,
    format: 'TV',
    episodes: 25,
    status: 'Finished',
    genres: ['Sports', 'Comedy'],
    synopsis: 'A short but determined player joins his high school volleyball team.',
    palette: [Color(0xFFF07A3C), Color(0xFF3A1F14)],
  ),
];

Anime animeById(int id) => mockCatalogue.firstWhere((a) => a.id == id);

const mockWatchlist = <WatchEntry>[
  WatchEntry(animeId: 154587, status: ListStatus.watching, watched: 3),
  WatchEntry(animeId: 171018, status: ListStatus.watching, watched: 7),
  WatchEntry(animeId: 151807, status: ListStatus.watching, watched: 10),
  WatchEntry(animeId: 161645, status: ListStatus.watching, watched: 15),
  WatchEntry(animeId: 163132, status: ListStatus.planned, watched: 0),
  WatchEntry(animeId: 137822, status: ListStatus.planned, watched: 0),
  WatchEntry(animeId: 150672, status: ListStatus.planned, watched: 0),
  WatchEntry(animeId: 140960, status: ListStatus.completed, watched: 25),
  WatchEntry(animeId: 20464, status: ListStatus.completed, watched: 25),
];

const mockLibrary = <LibraryFile>[
  LibraryFile(id: 'f1', fileName: 'Frieren_E01.mp4', sizeLabel: '1.1 GB', state: FileState.matched, animeId: 154587, episode: 1),
  LibraryFile(id: 'f2', fileName: 'Frieren_E02.mp4', sizeLabel: '1.1 GB', state: FileState.missing, animeId: 154587, episode: 2),
  LibraryFile(id: 'f3', fileName: 'Frieren_E03.mp4', sizeLabel: '1.2 GB', state: FileState.matched, animeId: 154587, episode: 3),
  LibraryFile(id: 'f4', fileName: 'Frieren_E04.mp4', sizeLabel: '1.2 GB', state: FileState.matched, animeId: 154587, episode: 4),
  LibraryFile(id: 'f5', fileName: 'dandadan_ep07.mkv', sizeLabel: '1.2 GB', state: FileState.matched, animeId: 171018, episode: 7),
  LibraryFile(
    id: 'f6',
    fileName: 'dandadan_ep08.mkv',
    sizeLabel: '1.2 GB',
    state: FileState.unmatched,
    suggestedAnimeId: 171018,
    suggestedEpisode: 8,
  ),
];

const mockProgress = <PlaybackProgress>[
  PlaybackProgress(animeId: 154587, episode: 4, position: Duration(minutes: 14, seconds: 2), duration: Duration(minutes: 23, seconds: 40)),
  PlaybackProgress(animeId: 171018, episode: 8, position: Duration(minutes: 5, seconds: 10), duration: Duration(minutes: 23, seconds: 40)),
];
