<master>
<property name="doc(title)">LTI Launch Test</property>


<h1>LTI Launch Test Page</h1>

<p>Simple page to test to connect to a LTI Tool Provider as a LTI Tool Consumer.
   You can use one of the following LTI Tool Emulators for general checks,
   or provide credentials to an actual LTI Tool Provider.
   The result is displayed inside an iframe below the LTI Request form.</p>

<h2>LTI Tool Emulators</h2>
<pre>URL: https://lti.tools/saltire/tp
Consumer Key: your choice
Secret: secret
</pre>

<pre>URL: https://www.tsugi.org/lti-test/tool.php
Key: 12345
Secret: secret
</pre>

<h2>LTI Request</h2>
<formtemplate id="zoom"></formtemplate>

<hr>
<h2>Result</h2>
@chunk;noquote@