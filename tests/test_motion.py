"""Caller-driven motion, static alternatives and bounded retained resources."""
import unittest
import os
import select
import signal
import termios
import test_compositions
import test_clipping
from test_drawing import drawing_session


class MotionTests(unittest.TestCase):
    def test_headless_state(self):
        test_clipping.ClippingTests().headless(fixture='ui-motion-state.zsh', marker='UI MOTION STATE PASS')

    def test_retained_frames_and_resources(self):
        drawing_session(self, 'wide', fixture='ui-motion.zsh', marker=b'UI MOTION PASS')



class MotionSession(test_compositions.RecipeSession):
    def __init__(self, case, option):
        self.delays = []
        super().__init__(case, option, fixture='motion-monitor.zsh')

    def read(self):
        while True:
            packet = super().read()
            if packet[0] != 'wait':
                return packet
            self.delays.append(int(packet[1]))

    def finish(self, sig=None, at_frame=False):
        if sig is None:
            packet = self.advance(b'q')
        else:
            if at_frame:
                os.write(self.control, b'interrupt\n')
            else:
                os.kill(self.pid, sig)
            packet = self.read()
        self.case.assertEqual(packet, ['done', 'cancelled', 'cancelled'])
        _, result = os.waitpid(self.pid, 0)
        self.reaped = True
        self.case.assertEqual(os.waitstatus_to_exitcode(result), 128 + sig if sig else 0)
        self.case.assertEqual(termios.tcgetattr(self.terminal), self.baseline)


class MotionMonitorTests(unittest.TestCase):
    def test_animated_resize_focus_and_idle(self):
        session = MotionSession(self, '--motion')
        try:
            frame = session.advance()
            self.assertEqual(frame[5:12], ['on', 'running', '0', '1', 'running', '0', '1'])
            self.assertEqual(session.advance()[7], '1')
            self.assertEqual(session.advance()[9:11], ['complete', '2'])
            self.assertEqual(session.advance(b' ')[6], 'paused')
            self.assertEqual(session.advance()[9:11], ['running', '1'])
            self.assertEqual(session.advance()[9:11], ['complete', '2'])
            # Release the presentation barrier: the next input call must block,
            # with no timeout-driven calls or frames over more than one old tick.
            os.write(session.control, b'continue\n')
            self.assertEqual(test_compositions.RecipeSession.read(session), ['wait', '-1'])
            self.assertEqual(select.select([session.report], [], [], 0.4)[0], [])
            os.write(session.terminal, b'2')
            self.assertEqual(session.read()[-1], '2')
            self.assertEqual(session.advance(b'j')[-2:], ['2', '2'])
            self.assertEqual(session.advance(size=(4, 20))[8:12], ['0', 'complete', '2', '0'])
            self.assertEqual(session.advance(size=(24, 80))[-2:], ['2', '2'])
            self.assertEqual(session.advance(b'a')[5], 'reduced')
            self.assertEqual(session.advance(b'a')[5], 'off')
            session.finish()
        finally:
            session.close()

    def test_signal_during_presentation(self):
        session = MotionSession(self, '--no-motion')
        try:
            session.advance()
            session.advance(b' ')
            session.finish(signal.SIGTERM, at_frame=True)
        finally:
            session.close()

    def test_static_and_signal_cleanup(self):
        for option in ('--reduced-motion', '--no-motion'):
            with self.subTest(option=option):
                session = MotionSession(self, option)
                try:
                    self.assertEqual(session.advance()[9:11], ['complete', '2'])
                    self.assertEqual(session.advance()[7], '0')
                    self.assertEqual(session.advance(b' ')[9:11], ['complete', '2'])
                    os.write(session.control, b'continue\n')
                    self.assertEqual(test_compositions.RecipeSession.read(session), ['wait', '-1'])
                    self.assertEqual(select.select([session.report], [], [], 0.4)[0], [])
                    session.finish(signal.SIGTERM if option == '--reduced-motion' else signal.SIGINT)
                finally:
                    session.close()
