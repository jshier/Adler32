import DataCompression
import Foundation

func simple_deflate(_ data: Data) throws -> Data {
    var output = Data([0x78, 0x5e]) // Header
    let compressedBody = try (data as NSData).compressed(using: .zlib) as Data
    output.append(compressedBody)
    var checksum = simple_adler32Checksum(of: data)
    output.append(Data(bytes: &checksum, count: MemoryLayout<UInt32>.size))

    return output
}

func deflate(_ data: Data) throws -> Data {
    var output = Data([0x78, 0x5e]) // Header
    let compressedBody = try (data as NSData).compressed(using: .zlib) as Data
    output.append(compressedBody)
    var checksum = adler32Checksum(of: data)
    output.append(Data(bytes: &checksum, count: MemoryLayout<UInt32>.size))

    return output
}

func dc_deflate(_ data: Data) -> Data {
    data.zip()!
}

// Swift port of libz algorithm from https://github.com/madler/zlib/blob/04f42ceca40f73e2978b50e93806c2a18c1281fc/adler32.c#L63
@inline(__always)
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

    return ((s2 << 16) | s1).bigEndian
}

@inline(__always)
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

    return ((s2 << 16) | s1).bigEndian
}

@inline(__always)
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

    return ((s2 << 16) | s1).bigEndian
}

@inline(__always)
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

    return ((s2 << 16) | s1).bigEndian
}

@inline(__always)
func dc_adler32(of data: Data) -> UInt32 {
    var adler = Adler32()
    adler.advance(withChunk: data)
    return adler.checksum.bigEndian
}

func performCompressionComparison(at bytes: Int, loops: Int) {
    let ints = [UInt32](repeating: 0, count: bytes / 4).map { _ in arc4random() }
    let randomBlob = Data(bytes: ints, count: bytes)

    let startComplex = CFAbsoluteTimeGetCurrent()
    var complexOutput = Data()
    for _ in 0..<loops {
        complexOutput = try! deflate(randomBlob)
    }
    let endComplex = CFAbsoluteTimeGetCurrent()

    let startSimple = CFAbsoluteTimeGetCurrent()
    var simpleOutput = Data()
    for _ in 0..<loops {
        simpleOutput = try! simple_deflate(randomBlob)
    }
    let endSimple = CFAbsoluteTimeGetCurrent()

    let startLibrary = CFAbsoluteTimeGetCurrent()
    var libraryOutput = Data()
    for _ in 0..<loops {
        libraryOutput = dc_deflate(randomBlob)
    }
    let endLibrary = CFAbsoluteTimeGetCurrent()

    let simpleDuration = endSimple - startSimple
    let complexDuration = endComplex - startComplex
    let libraryDuration = endLibrary - startLibrary
    print("Simple:  \(simpleDuration)s")
    print("Complex: \(complexDuration)")
    print("Library: \(libraryDuration)")
    print(simpleOutput == libraryOutput && complexOutput == libraryOutput)
    print("Simple is \(simpleDuration / libraryDuration)x slower than library.")
    print("Complex is \(complexDuration / libraryDuration)x slower than library.")
}

func performComparison(at bytes: Int, loops: Int, sleepBetweenRuns: Bool = false) {
    let ints = [UInt32](repeating: 0, count: bytes / 4).map { _ in arc4random() }
    let randomBlob = Data(bytes: ints, count: bytes)

    let startWorst = CFAbsoluteTimeGetCurrent()
    var worstOutput: UInt32 = 0
    for _ in 0..<loops {
        worstOutput = worst_adler32Checksum(of: randomBlob)
    }
    let endWorst = CFAbsoluteTimeGetCurrent()

    if sleepBetweenRuns {
        sleep(1)
    }

    let startSimple = CFAbsoluteTimeGetCurrent()
    var simpleOutput: UInt32 = 0
    for _ in 0..<loops {
        simpleOutput = simple_adler32Checksum(of: randomBlob)
    }
    let endSimple = CFAbsoluteTimeGetCurrent()

    if sleepBetweenRuns {
        sleep(1)
    }

    let startIm = CFAbsoluteTimeGetCurrent()
    var imOutput: UInt32 = 0
    for _ in 0..<loops {
        imOutput = im_adler32Checksum(of: randomBlob)
    }
    let endIm = CFAbsoluteTimeGetCurrent()

    if sleepBetweenRuns {
        sleep(1)
    }

    let startComplex = CFAbsoluteTimeGetCurrent()
    var complexOutput: UInt32 = 0
    for _ in 0..<loops {
        complexOutput = adler32Checksum(of: randomBlob)
    }
    let endComplex = CFAbsoluteTimeGetCurrent()

    if sleepBetweenRuns {
        sleep(1)
    }

    let startLibrary = CFAbsoluteTimeGetCurrent()
    var libraryOutput: UInt32 = 0
    for _ in 0..<loops {
        libraryOutput = dc_adler32(of: randomBlob)
    }
    let endLibrary = CFAbsoluteTimeGetCurrent()

    let worstDuration = endWorst - startWorst
    let simpleDuration = endSimple - startSimple
    let imDuration = endIm - startIm
    let complexDuration = endComplex - startComplex
    let libraryDuration = endLibrary - startLibrary

    print("Worst:     \(worstDuration)s")
    print("Simple:    \(simpleDuration)s")
    print("Immediate: \(imDuration)")
    print("Complex:   \(complexDuration)s")
    print("Library:   \(libraryDuration)s")

    print("Worst is \(worstDuration / libraryDuration)x slower than library.")
    print("Simple is \(simpleDuration / libraryDuration)x slower than library.")
    print("Simple is \(worstDuration / simpleDuration)x faster than worst.")
    print("Immediate is \(imDuration / libraryDuration)x slower than library.")
    print("Immediate is \(worstDuration / imDuration)x faster than worst.")
    print("Complex is \(complexDuration / libraryDuration)x slower than library.")
    print("Complex is \(worstDuration / complexDuration)x faster than worst.")

    if worstOutput == libraryOutput && simpleOutput == libraryOutput && complexOutput == libraryOutput && imOutput == libraryOutput {
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
