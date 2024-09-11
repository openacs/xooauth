<master>
<property name="doc(title)">@title;literal@</property>

<h1>@name@ Authorization</h2>

<ul>
<if @login_url@ not nil><li><a href="@login_url@">Login via @name@</a></if>
<if @logout_url@ not nil><li><a href="@logout_url@">Logout from @name@</a></if>
</ul>

<if @error@ not nil>
<h3>Error:</h3>
<pre>@error@</pre>
</if>

<if @claims@ not nil>
<h3>Claims:</h3>
<pre>
@cooked_claims@
</pre>
</if>

<if @cooked_data@ not nil>
<h3>Response Data:</h3>
<pre>
@cooked_data@
</pre>
</if>
