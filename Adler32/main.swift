import DataCompression
import Foundation

// Swift port of libz algorithm from https://github.com/madler/zlib/blob/04f42ceca40f73e2978b50e93806c2a18c1281fc/adler32.c#L63
// About 7x slower than Apple's libz.
func adler32Checksum(of data: Data) -> UInt32 {
    var s1: UInt32 = 1 & 0xffff
    var s2: UInt32 = (1 >> 16) & 0xffff
    let prime: UInt32 = 65521

    data.withUnsafeBytes { pointer in
        if pointer.count == 1, let byte = pointer.first {
            s1 += UInt32(byte)
            s1 %= prime
            s2 += s1
            s2 %= prime
        } else if pointer.count < 16 {
            var position = 0
            while position < pointer.count {
                s1 += UInt32(pointer[position])
                s2 += s1
                position += 1
            }

            s1 %= prime
            s2 %= prime
        } else {
            var remainingCount = pointer.count
            // maxIteration is the largest n such that 255n(n + 1) / 2 + (n + 1)(prime - 1) <= 2^32 - 1, per libz.
            let maxIteration = 5552
            var position = 0

            while remainingCount >= maxIteration {
                remainingCount -= maxIteration
                var loops = maxIteration / 16 // evenly divisible

                repeat {
                    var innerPosition = 0
                    while innerPosition < 16 {
                        s1 += UInt32(pointer[position + innerPosition])
                        s2 += s1
                        innerPosition += 1
                    }
                    s1 %= prime
                    s2 %= prime
                    position += innerPosition
                    loops -= 1
                } while loops > 0
            }

            if remainingCount > 0 {
                while position < pointer.count {
                    s1 += UInt32(pointer[position])
                    s2 += s1
                    remainingCount -= 1
                    position += 1
                }

                s1 %= prime
                s2 %= prime
            }
        }
    }

    return ((s2 << 16) | s1)
}

func loadMany_adler32Checksum(of data: Data) -> UInt32 {
    var s1: UInt32 = 1 & 0xffff
    var s2: UInt32 = (1 >> 16) & 0xffff
    let prime: UInt32 = 65521

    data.withUnsafeBytes { pointer in
        if pointer.count == 1, let byte = pointer.first {
            s1 += UInt32(byte)
            s1 %= prime
            s2 += s1
            s2 %= prime
        } else if pointer.count < 16 {
            var position = 0
            while position < pointer.count {
                s1 += UInt32(pointer[position])
                s2 += s1
                position += 1
            }

            s1 %= prime
            s2 %= prime
        } else {
            var remainingCount = pointer.count
            // maxIteration is the largest n such that 255n(n + 1) / 2 + (n + 1)(prime - 1) <= 2^32 - 1, per libz.
            let maxIteration = 5552
            var position = 0

            while remainingCount >= maxIteration {
                remainingCount -= maxIteration
                var loops = maxIteration / 16 // evenly divisible

                repeat {
                    let firstEight = pointer.load(fromByteOffset: position, as: UInt64.self)
                    position += 8
                    let secondEight = pointer.load(fromByteOffset: position, as: UInt64.self)
                    position += 8

                    for shift in stride(from: 0, through: 56, by: 8) {
                        s1 += UInt32((firstEight >> shift) & 0xFF)
                        s2 += s1
                    }

                    for shift in stride(from: 0, through: 56, by: 8) {
                        s1 += UInt32((secondEight >> shift) & 0xFF)
                        s2 += s1
                    }

                    s1 %= prime
                    s2 %= prime
                    loops -= 1
                } while loops > 0
            }

            if remainingCount > 0 {
                while position < pointer.count {
                    s1 += UInt32(pointer[position])
                    s2 += s1
                    remainingCount -= 1
                    position += 1
                }

                s1 %= prime
                s2 %= prime
            }
        }
    }

    return ((s2 << 16) | s1)
}

func wrapping_adler32Checksum(of data: Data) -> UInt32 {
    var s1: UInt32 = 1 & 0xffff
    var s2: UInt32 = (1 >> 16) & 0xffff
    let prime: UInt32 = 65521

    data.withUnsafeBytes { pointer in
        if pointer.count == 1, let byte = pointer.first {
            s1 &+= UInt32(byte)
            s1 %= prime
            s2 &+= s1
            s2 %= prime
        } else if pointer.count < 16 {
            var position = 0
            while position < pointer.count {
                s1 &+= UInt32(pointer[position])
                s2 &+= s1
                position &+= 1
            }

            s1 %= prime
            s2 %= prime
        } else {
            var remainingCount = pointer.count
            // maxIteration is the largest n such that 255n(n + 1) / 2 + (n + 1)(prime - 1) <= 2^32 - 1, per libz.
            let maxIteration = 5552
            var position = 0

            while remainingCount >= maxIteration {
                remainingCount -= maxIteration
                var loops = maxIteration / 16 // evenly divisible

                repeat {
                    var innerPosition = 0
                    while innerPosition < 16 {
                        s1 &+= UInt32(pointer[position + innerPosition])
                        s2 &+= s1
                        innerPosition &+= 1
                    }
                    s1 %= prime
                    s2 %= prime
                    position &+= innerPosition
                    loops &-= 1
                } while loops > 0
            }

            if remainingCount > 0 {
                while position < pointer.count {
                    s1 &+= UInt32(pointer[position])
                    s2 &+= s1
                    remainingCount &-= 1
                    position &+= 1
                }

                s1 %= prime
                s2 %= prime
            }
        }
    }

    return ((s2 << 16) | s1)
}

// Ported from https://github.com/kelvin13/swift-png/blob/master/Sources/PNG/LZ77/LZ77.Inflator.swift#L19-L51
// Only 6.5x slower than Apple's libz.
func taylor_adler32Checksum(of data: Data) -> UInt32 {
    data.withUnsafeBytes { pointer in
        let (q, r): (Int, Int) = data.count.quotientAndRemainder(dividingBy: 5552)
        var (single, double): (UInt32, UInt32) = (1 & 0xffff, (1 >> 16) & 0xffff)

        for i: Int in 0 ..< q {
            for j: Int in 5552 * i ..< 5552 * (i + 1) {
                single &+= .init(pointer[j])
                double &+= single
            }
            single %= 65521
            double %= 65521
        }

        for j: Int in 5552 * q ..< 5552 * q + r {
            single &+= .init(pointer[j])
            double &+= single
        }

        return ((double % 65521) << 16 | (single % 65521))
    }
}

func im_adler32Checksum(of data: Data) -> UInt32 {
    var s1: UInt32 = 1 & 0xffff
    var s2: UInt32 = (1 >> 16) & 0xffff
    let prime: UInt32 = 65521

    data.withUnsafeBytes { pointer in
        for byte in pointer {
            s1 += UInt32(byte)
            s1 %= prime
            s2 += s1
            s2 %= prime
        }
    }

    return ((s2 << 16) | s1)
}

func simple_adler32Checksum(of data: Data) -> UInt32 {
    var s1: UInt32 = 1 & 0xffff
    var s2: UInt32 = (1 >> 16) & 0xffff
    let prime: UInt32 = 65521

    data.withUnsafeBytes { pointer in
        for byte in pointer {
            s1 += UInt32(byte)
            if s1 >= prime { s1 = s1 % prime }
            s2 += s1
            if s2 >= prime { s2 = s2 % prime }
        }
    }

    return ((s2 << 16) | s1)
}

func worst_adler32Checksum(of data: Data) -> UInt32 {
    var s1: UInt32 = 1 & 0xffff
    var s2: UInt32 = (1 >> 16) & 0xffff
    let prime: UInt32 = 65521

    for byte in data {
        s1 += UInt32(byte)
        if s1 >= prime { s1 = s1 % prime }
        s2 += s1
        if s2 >= prime { s2 = s2 % prime }
    }

    return ((s2 << 16) | s1)
}

import zlib
func libz_adler32Checksum(of data: Data) -> UInt32 {
  data.withUnsafeBytes { buffer in
      UInt32(adler32(1, buffer.baseAddress, UInt32(buffer.count)))
  }
}

#if arch(arm64)
import _Builtin_intrinsics.arm.neon

// Port of Chromium's vectorized version by Tony Allevato
// https://forums.swift.org/t/optimizing-swift-adler32-checksum/63596/21
// Ever so slightly faster than the C version from Apple's zlib.
func neon_adler32Checksum(of data: Data) -> UInt32 {
  data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) -> UInt32 in
    let BASE: UInt32 = 65521
    let NMAX: UInt32 = 5552

    // Split Adler-32 into component sums.
    var s1: UInt32 = 1 & 0xffff
    var s2: UInt32 = (1 >> 16) & 0xffff

    var len = buf.count
    var offset = 0

    // Serially compute s1 & s2, until the data is 16-byte aligned.
    // FIXME: Including this blows up the codegen and slows it down from
    // ~1x the library to ~7x the library. Why?
//    let base = Int(bitPattern: buf.baseAddress)
//    if base & 15 != 0 {
//      while (base + offset) & 15 != 0 {
//        s1 += UInt32(buf[offset])
//        s2 += s1
//        offset += 1
//        len -= 1
//      }
//      if s1 >= BASE {
//        s1 -= BASE
//      }
//      s2 %= BASE
//    }
    // Process the data in blocks.
    let BLOCK_SIZE: UInt32 = 1 << 5
    var blocks = UInt32(len) / BLOCK_SIZE
    len -= Int(blocks * BLOCK_SIZE)
    while blocks != 0 {
      var n = NMAX / BLOCK_SIZE  // The NMAX constraint.
      if n > blocks {
        n = blocks
      }
      blocks -= n

      // Process n blocks of data. At most NMAX data bytes can be
      // processed before s2 must be reduced modulo BASE.
      var v_s2 = SIMD4<UInt32>(0, 0, 0, s1 * n)
      var v_s1 = SIMD4<UInt32>(0, 0, 0, 0)
      var v_column_sum_1 = SIMD8<UInt16>(repeating: 0)
      var v_column_sum_2 = SIMD8<UInt16>(repeating: 0)
      var v_column_sum_3 = SIMD8<UInt16>(repeating: 0)
      var v_column_sum_4 = SIMD8<UInt16>(repeating: 0)

      repeat {
        // Load 32 input bytes.
        let bytes1 = SIMD16<UInt8>(buf[offset + 0..<offset + 16])
        let bytes2 = SIMD16<UInt8>(buf[offset + 16..<offset + 32])

        // Add previous block byte sum to v_s2.
        v_s2 &+= v_s1

        // Horizontally add the bytes for s1.
        v_s1 = vpadalq_u16(
          v_s1,
          vpadalq_u8(vpaddlq_u8(bytes1), bytes2))

        // Vertically add the bytes for s2. `init(truncatingIfNeeded:)` to
        // widen.
        v_column_sum_1 &+= SIMD8<UInt16>(truncatingIfNeeded: bytes1.lowHalf)
        v_column_sum_2 &+= SIMD8<UInt16>(truncatingIfNeeded: bytes1.highHalf)
        v_column_sum_3 &+= SIMD8<UInt16>(truncatingIfNeeded: bytes2.lowHalf)
        v_column_sum_4 &+= SIMD8<UInt16>(truncatingIfNeeded: bytes2.highHalf)

        offset += Int(BLOCK_SIZE)
        n -= 1
      } while n != 0

      v_s2 = v_s2 &<< 5

      // Multiply-add bytes by [ 32, 31, 30, ... ] for s2.
      v_s2 = vmlal_u16(v_s2, v_column_sum_1.lowHalf,  SIMD4<UInt16>(32, 31, 30, 29))
      v_s2 = vmlal_u16(v_s2, v_column_sum_1.highHalf, SIMD4<UInt16>(28, 27, 26, 25))
      v_s2 = vmlal_u16(v_s2, v_column_sum_2.lowHalf,  SIMD4<UInt16>(24, 23, 22, 21))
      v_s2 = vmlal_u16(v_s2, v_column_sum_2.highHalf, SIMD4<UInt16>(20, 19, 18, 17))
      v_s2 = vmlal_u16(v_s2, v_column_sum_3.lowHalf,  SIMD4<UInt16>(16, 15, 14, 13))
      v_s2 = vmlal_u16(v_s2, v_column_sum_3.highHalf, SIMD4<UInt16>(12, 11, 10,  9))
      v_s2 = vmlal_u16(v_s2, v_column_sum_4.lowHalf,  SIMD4<UInt16>( 8,  7,  6,  5))
      v_s2 = vmlal_u16(v_s2, v_column_sum_4.highHalf, SIMD4<UInt16>( 4,  3,  2,  1))

      // Sum epi32 ints v_s1(s2) and accumulate in s1(s2).
      let sum1 = v_s1.lowHalf &+ v_s1.highHalf
      let sum2 = v_s2.lowHalf &+ v_s2.highHalf
      let s1s2 = vpadd_u32(sum1, sum2)

      s1 += s1s2[0]
      s2 += s1s2[1]

      // Reduce.
      s1 %= BASE
      s2 %= BASE
    }

    // Handle leftover data.
    if len != 0 {
      if len >= 16 {
        for _ in 0..<16 {
          s1 += UInt32(buf[offset])
          s2 += s1
          offset += 1
        }
        len -= 16
      }

      while len != 0 {
        s1 += UInt32(buf[offset])
        s2 += s1
        offset += 1
        len -= 1
      }
      if s1 >= BASE {
        s1 -= BASE
      }
      s2 %= BASE
    }

    // Return the recombined sums.
    return (s1 | (s2 << 16))
  }
}
#endif

// From DataCompression, wraps Apple's zlib.
func dc_adler32(of data: Data) -> UInt32 {
    var adler = Adler32()
    adler.advance(withChunk: data)
    return adler.checksum
}

func performComparison(at bytes: Int, loops: Int, sleepBetweenRuns: Bool = false) {
    let ints = [UInt32](repeating: 0, count: bytes / 4).map { _ in arc4random() }
    let randomBlob = Data(bytes: ints, count: bytes)
    var inputs: [String: (Data) -> UInt32] = [
        "Worst": worst_adler32Checksum(of:),
        "Simple": simple_adler32Checksum(of:),
        "Immediate": im_adler32Checksum(of:),
        "Complex": adler32Checksum(of:),
        "Wrapping": wrapping_adler32Checksum(of:),
        "LoadMany": loadMany_adler32Checksum(of:),
        "Taylor": taylor_adler32Checksum(of:),
        "AppleLibZ": libz_adler32Checksum(of:),
        "Library": dc_adler32(of:)
    ]

    #if arch(arm64)
    inputs["Vector"] = neon_adler32Checksum(of:)
    #endif

    var outputs: [String: (checksum: UInt32, duration: Double)] = [:]

    for input in inputs {
        let checksum = input.value
        let start = CFAbsoluteTimeGetCurrent()
        var output: UInt32 = 0
        for _ in 0..<loops {
            output = checksum(randomBlob)
        }
        let end = CFAbsoluteTimeGetCurrent()
        outputs[input.key] = (checksum: output, duration: end - start)

        if sleepBetweenRuns {
            sleep(1)
        }
    }

    let worstDuration = outputs["Worst"]!.duration
    let simpleDuration = outputs["Simple"]!.duration
    let imDuration = outputs["Immediate"]!.duration
    let complexDuration = outputs["Complex"]!.duration
    let wrappingDuration = outputs["Wrapping"]!.duration
    let loadManyDuration = outputs["LoadMany"]!.duration
    let taylorDuration = outputs["Taylor"]!.duration
    let libzDuration = outputs["AppleLibZ"]!.duration
    #if arch(arm64)
    let vectorDuration = outputs["Vector"]!.duration
    #endif
    let libraryDuration = outputs["Library"]!.duration

    print("Worst:     \(worstDuration)s")
    print("Simple:    \(simpleDuration)s")
    print("Immediate: \(imDuration)s")
    print("Complex:   \(complexDuration)s")
    print("Wrapping:  \(wrappingDuration)s")
    print("LoadMany:  \(loadManyDuration)s")
    print("Taylor:    \(taylorDuration)s")
    print("AppleLibZ: \(libzDuration)s")
    #if arch(arm64)
    print("Vector:    \(vectorDuration)s")
    #endif
    print("Library:   \(libraryDuration)s")

    print("Worst is     \(worstDuration / libraryDuration)x slower than library.")
    print("Simple is    \(simpleDuration / libraryDuration)x slower than library.")
    print("Simple is    \(worstDuration / simpleDuration)x faster than worst.")
    print("Immediate is \(imDuration / libraryDuration)x slower than library.")
    print("Immediate is \(worstDuration / imDuration)x faster than worst.")
    print("Complex is   \(complexDuration / libraryDuration)x slower than library.")
    print("Complex is   \(worstDuration / complexDuration)x faster than worst.")
    print("Wrapping is  \(wrappingDuration / libraryDuration)x slower than library.")
    print("Wrapping is  \(worstDuration / wrappingDuration)x faster than worst.")
    print("LoadMany is  \(loadManyDuration / libraryDuration)x slower than library.")
    print("LoadMany is  \(worstDuration / loadManyDuration)x faster than worst.")
    print("Taylor is    \(taylorDuration / libraryDuration)x slower than library.")
    print("Taylor is    \(worstDuration / taylorDuration)x faster than worst.")
    print("AppleLibZ is \(libzDuration / libraryDuration)x slower than library.")
    print("AppleLibZ is \(worstDuration / libzDuration)x faster than worst.")
    #if arch(arm64)
    print("Vector is    \(vectorDuration / libraryDuration)x slower than library.")
    print("Vector is    \(worstDuration / vectorDuration)x faster than worst.")
    #endif

    if outputs.values.map(\.checksum).allSatisfy({ $0 == outputs["Library"]!.checksum }) {
        print("All outputs match!")
    } else {
        print("Output mismatch!!!")
    }
}

//var throwaway = Adler32()
//throwaway.advance(withChunk: Data())
//
//print("At 0B:")
//performComparison(at: 0, loops: 10000)
//
//print("At 1B:")
//performComparison(at: 1, loops: 10000)
//
//print("At 16B:")
//performComparison(at: 16, loops: 10000)
//
//print("At 5551B:")
//performComparison(at: 5551, loops: 10000)
//
//for i in stride(from: 1, through: 1024, by: 128) {
//    print("At \(i)KB:")
//    performComparison(at: i * 1024, loops: 10)
//}
//
//for i in 1...16 {
//    print("At \(i)MB:")
//    performComparison(at: i * 1024 * 1024, loops: 10)
//}

//print("Deflate 16MB:")
//performComparison(at: 16 * 1024 * 1024, loops: 10)

performComparison(at: 16 * 1024 * 1024, loops: 10, sleepBetweenRuns: false)
//performComparison(at: 15, loops: 10000000, sleepBetweenRuns: false)
