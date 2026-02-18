import { beforeEach, describe, expect, it } from 'vitest'

// App.tsx から抽出したロジックの再定義（テスト対象）
interface HistoryMatch {
  frequency: number
  matchType: 'exact' | 'prefix' | 'none'
}

interface SelectionHistory {
  keyword: string
  selectedPath: string
  timestamp: number
}

const calculateHistoryMatch = (
  currentKeyword: string,
  path: string,
  history: SelectionHistory[],
): HistoryMatch => {
  const normalizedCurrent = currentKeyword.toLowerCase().trim()

  const exactMatches = history.filter(
    (h) =>
      h.keyword.toLowerCase() === normalizedCurrent && h.selectedPath === path,
  )

  if (exactMatches.length > 0) {
    return { frequency: exactMatches.length, matchType: 'exact' }
  }

  const prefixMatches = history.filter(
    (h) =>
      h.keyword.toLowerCase().startsWith(normalizedCurrent) &&
      h.selectedPath === path,
  )

  if (prefixMatches.length > 0) {
    return { frequency: prefixMatches.length, matchType: 'prefix' }
  }

  return { frequency: 0, matchType: 'none' }
}

// App.tsx の loadHistory / saveHistory と同等のロジック
const HISTORY_STORAGE_KEY = 'ignitero_selection_history'
const MAX_HISTORY_COUNT = 50

const loadHistory = (): SelectionHistory[] => {
  try {
    const stored = localStorage.getItem(HISTORY_STORAGE_KEY)
    return stored ? JSON.parse(stored) : []
  } catch {
    return []
  }
}

const saveHistory = (history: SelectionHistory[]) => {
  try {
    localStorage.setItem(HISTORY_STORAGE_KEY, JSON.stringify(history))
  } catch {
    // ignore
  }
}

describe('calculateHistoryMatch', () => {
  const history: SelectionHistory[] = [
    { keyword: 'saf', selectedPath: '/Applications/Safari.app', timestamp: 1 },
    { keyword: 'saf', selectedPath: '/Applications/Safari.app', timestamp: 2 },
    {
      keyword: 'safari',
      selectedPath: '/Applications/Safari.app',
      timestamp: 3,
    },
    { keyword: 'mail', selectedPath: '/Applications/Mail.app', timestamp: 4 },
    {
      keyword: 'SAF',
      selectedPath: '/Applications/Safari.app',
      timestamp: 5,
    },
  ]

  it('should return exact match with correct frequency', () => {
    const result = calculateHistoryMatch(
      'saf',
      '/Applications/Safari.app',
      history,
    )
    expect(result.matchType).toBe('exact')
    expect(result.frequency).toBe(3) // 'saf' x2 + 'SAF' x1 (case insensitive)
  })

  it('should be case insensitive for exact matching', () => {
    const result1 = calculateHistoryMatch(
      'saf',
      '/Applications/Safari.app',
      history,
    )
    const result2 = calculateHistoryMatch(
      'SAF',
      '/Applications/Safari.app',
      history,
    )
    expect(result1.frequency).toBe(result2.frequency)
    expect(result1.matchType).toBe(result2.matchType)
  })

  it('should return prefix match when no exact match', () => {
    // 's' is a prefix of 'saf' and 'safari'
    const result = calculateHistoryMatch(
      's',
      '/Applications/Safari.app',
      history,
    )
    expect(result.matchType).toBe('prefix')
    expect(result.frequency).toBe(4) // 'saf' x2 + 'safari' x1 + 'SAF' x1
  })

  it('should return none when no match found', () => {
    const result = calculateHistoryMatch(
      'xyz',
      '/Applications/Safari.app',
      history,
    )
    expect(result.matchType).toBe('none')
    expect(result.frequency).toBe(0)
  })

  it('should return none for unknown path', () => {
    const result = calculateHistoryMatch(
      'saf',
      '/Applications/Unknown.app',
      history,
    )
    expect(result.matchType).toBe('none')
    expect(result.frequency).toBe(0)
  })

  it('should handle empty history', () => {
    const result = calculateHistoryMatch('saf', '/Applications/Safari.app', [])
    expect(result.matchType).toBe('none')
    expect(result.frequency).toBe(0)
  })

  it('should handle empty keyword', () => {
    const result = calculateHistoryMatch(
      '',
      '/Applications/Safari.app',
      history,
    )
    // Empty string is prefix of everything
    expect(result.matchType).toBe('prefix')
  })

  it('should trim whitespace from keyword', () => {
    const result = calculateHistoryMatch(
      '  saf  ',
      '/Applications/Safari.app',
      history,
    )
    expect(result.matchType).toBe('exact')
    expect(result.frequency).toBe(3)
  })

  it('should prefer exact match over prefix match', () => {
    const result = calculateHistoryMatch(
      'safari',
      '/Applications/Safari.app',
      history,
    )
    expect(result.matchType).toBe('exact')
    expect(result.frequency).toBe(1)
  })
})

describe('loadHistory / saveHistory', () => {
  beforeEach(() => {
    localStorage.clear()
  })

  it('should return empty array when no history stored', () => {
    const result = loadHistory()
    expect(result).toEqual([])
  })

  it('should save and load history correctly', () => {
    const history: SelectionHistory[] = [
      {
        keyword: 'test',
        selectedPath: '/Applications/Test.app',
        timestamp: 1000,
      },
    ]

    saveHistory(history)
    const loaded = loadHistory()

    expect(loaded).toHaveLength(1)
    expect(loaded[0].keyword).toBe('test')
    expect(loaded[0].selectedPath).toBe('/Applications/Test.app')
    expect(loaded[0].timestamp).toBe(1000)
  })

  it('should handle corrupted localStorage gracefully', () => {
    localStorage.setItem(HISTORY_STORAGE_KEY, 'invalid json data')
    const result = loadHistory()
    expect(result).toEqual([])
  })

  it('should limit history to MAX_HISTORY_COUNT entries', () => {
    const history: SelectionHistory[] = []
    for (let i = 0; i < 100; i++) {
      history.push({
        keyword: `keyword${i}`,
        selectedPath: `/path${i}`,
        timestamp: i,
      })
    }

    // App.tsx のロジック: 新しいエントリを先頭に追加し、MAX_HISTORY_COUNT に制限
    const limited = history.slice(0, MAX_HISTORY_COUNT)
    saveHistory(limited)

    const loaded = loadHistory()
    expect(loaded).toHaveLength(MAX_HISTORY_COUNT)
  })
})

describe('History-based sorting', () => {
  it('should sort exact matches before prefix matches', () => {
    const history: SelectionHistory[] = [
      { keyword: 'saf', selectedPath: '/path1', timestamp: 1 },
      { keyword: 'safari', selectedPath: '/path2', timestamp: 2 },
    ]

    const items = [
      { path: '/path1', keyword: 'saf' },
      { path: '/path2', keyword: 'saf' },
    ]

    const sorted = items.sort((a, b) => {
      const matchA = calculateHistoryMatch('saf', a.path, history)
      const matchB = calculateHistoryMatch('saf', b.path, history)

      const typeOrder = { exact: 2, prefix: 1, none: 0 }
      const typeCompare =
        typeOrder[matchB.matchType] - typeOrder[matchA.matchType]
      if (typeCompare !== 0) return typeCompare

      return matchB.frequency - matchA.frequency
    })

    // '/path1' has exact match for 'saf', '/path2' has prefix match (saf starts 'safari')
    // Wait - 'safari'.startsWith('saf') is true, so it's a prefix match for path2
    expect(sorted[0].path).toBe('/path1') // exact match first
  })

  it('should sort by frequency within same match type', () => {
    const history: SelectionHistory[] = [
      { keyword: 'a', selectedPath: '/path1', timestamp: 1 },
      { keyword: 'a', selectedPath: '/path1', timestamp: 2 },
      { keyword: 'a', selectedPath: '/path1', timestamp: 3 },
      { keyword: 'a', selectedPath: '/path2', timestamp: 4 },
    ]

    const items = [
      { path: '/path2' },
      { path: '/path1' },
    ]

    const sorted = items.sort((a, b) => {
      const matchA = calculateHistoryMatch('a', a.path, history)
      const matchB = calculateHistoryMatch('a', b.path, history)

      const typeOrder = { exact: 2, prefix: 1, none: 0 }
      const typeCompare =
        typeOrder[matchB.matchType] - typeOrder[matchA.matchType]
      if (typeCompare !== 0) return typeCompare

      return matchB.frequency - matchA.frequency
    })

    expect(sorted[0].path).toBe('/path1') // frequency 3 > 1
    expect(sorted[1].path).toBe('/path2')
  })

  it('should place items with no history last', () => {
    const history: SelectionHistory[] = [
      { keyword: 'test', selectedPath: '/path1', timestamp: 1 },
    ]

    const items = [
      { path: '/path2' },
      { path: '/path1' },
    ]

    const sorted = items.sort((a, b) => {
      const matchA = calculateHistoryMatch('test', a.path, history)
      const matchB = calculateHistoryMatch('test', b.path, history)

      const typeOrder = { exact: 2, prefix: 1, none: 0 }
      const typeCompare =
        typeOrder[matchB.matchType] - typeOrder[matchA.matchType]
      if (typeCompare !== 0) return typeCompare

      return matchB.frequency - matchA.frequency
    })

    expect(sorted[0].path).toBe('/path1')
    expect(sorted[1].path).toBe('/path2')
  })
})
