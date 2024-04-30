package logstorage

import (
	"fmt"
	"sync/atomic"
)

type pipeHead struct {
	n uint64
}

func (ph *pipeHead) String() string {
	return fmt.Sprintf("head %d", ph.n)
}

func (ph *pipeHead) newPipeProcessor(_ int, _ <-chan struct{}, cancel func(), ppBase pipeProcessor) pipeProcessor {
	if ph.n == 0 {
		// Special case - notify the caller to stop writing data to the returned pipeHeadProcessor
		cancel()
	}
	return &pipeHeadProcessor{
		ph:     ph,
		cancel: cancel,
		ppBase: ppBase,
	}
}

type pipeHeadProcessor struct {
	ph     *pipeHead
	cancel func()
	ppBase pipeProcessor

	rowsProcessed atomic.Uint64
}

func (hpp *pipeHeadProcessor) writeBlock(workerID uint, br *blockResult) {
	rowsProcessed := hpp.rowsProcessed.Add(uint64(len(br.timestamps)))
	if rowsProcessed <= hpp.ph.n {
		// Fast path - write all the rows to ppBase.
		hpp.ppBase.writeBlock(workerID, br)
		return
	}

	// Slow path - overflow. Write the remaining rows if needed.
	rowsProcessed -= uint64(len(br.timestamps))
	if rowsProcessed >= hpp.ph.n {
		// Nothing to write. There is no need in cancel() call, since it has been called by another goroutine.
		return
	}

	// Write remaining rows.
	keepRows := hpp.ph.n - rowsProcessed
	br.truncateRows(int(keepRows))
	hpp.ppBase.writeBlock(workerID, br)

	// Notify the caller that it should stop passing more data to writeBlock().
	hpp.cancel()
}

func (hpp *pipeHeadProcessor) flush() error {
	return nil
}

func parsePipeHead(lex *lexer) (*pipeHead, error) {
	if !lex.mustNextToken() {
		return nil, fmt.Errorf("missing the number of head rows to return")
	}
	n, err := parseUint(lex.token)
	if err != nil {
		return nil, fmt.Errorf("cannot parse the number of head rows to return %q: %w", lex.token, err)
	}
	lex.nextToken()
	ph := &pipeHead{
		n: n,
	}
	return ph, nil
}
