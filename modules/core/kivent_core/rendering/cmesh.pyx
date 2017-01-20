# cython: profile=True
# cython: embedsignature=True

from ilh import loggdesc_begin, loggdesc_end

from kivy.graphics.instructions cimport VertexInstruction
from kivy.logger import Logger

from kivent_core.rendering.batching cimport IndexedBatch
include "opcodes.pxi"
include "common.pxi"


cdef class CMesh(VertexInstruction):

    def __init__(self, **kwargs):
        VertexInstruction.__init__(self, **kwargs)
        cdef IndexedBatch batch = kwargs.get('batch')
        self._batch = batch


    def __dealloc__(self):
        self._batch.clear_frames()

    cdef int apply(self) except -1:
        loggdesc_begin('CMesh.apply')
        if self.flags & GI_NEEDS_UPDATE:
            self._batch.current_frame += 1
            Logger.debug("advanced frame to %s", self._batch.current_frame)
            self.flag_update_done()
        self._batch.draw_frame()
        loggdesc_end()
