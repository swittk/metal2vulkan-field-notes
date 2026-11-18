#!/usr/bin/env python3
# Set the experimental D-Bus polling interval on a running patched QEMU.
import argparse,json,os,socket
from pathlib import Path

parser=argparse.ArgumentParser(description='Set the experimental QEMU D-Bus polling interval.')
parser.add_argument('socket',type=Path)
parser.add_argument('milliseconds',type=int)
args=parser.parse_args()
if not 1<=args.milliseconds<=1000:
    parser.error('milliseconds must be between 1 and 1000')
path=args.socket.resolve()
os.chdir(path.parent)  # UNIX-domain socket paths have a short length limit.
with socket.socket(socket.AF_UNIX) as connection:
    connection.settimeout(10)
    connection.connect(path.name)
    with connection.makefile('rwb') as stream:
        greeting=json.loads(stream.readline())
        if 'QMP' not in greeting:
            raise RuntimeError('Expected a QMP greeting')
        def command(name,arguments=None):
            message={'execute':name}
            if arguments is not None:
                message['arguments']=arguments
            stream.write((json.dumps(message)+'\n').encode())
            stream.flush()
            while True:
                line=stream.readline()
                if not line:
                    raise EOFError('QMP closed before replying')
                reply=json.loads(line)
                if 'error' in reply:
                    raise RuntimeError(reply['error'])
                if 'return' in reply:
                    return reply['return']
        command('qmp_capabilities')
        property={'path':'/objects/dbus-display','property':'refresh-interval'}
        before=command('qom-get',property)
        command('qom-set',{**property,'value':args.milliseconds})
        after=command('qom-get',property)
        if after!=args.milliseconds:
            raise RuntimeError('QMP did not retain the requested interval')
        print(json.dumps({'before_ms':before,'after_ms':after}))
